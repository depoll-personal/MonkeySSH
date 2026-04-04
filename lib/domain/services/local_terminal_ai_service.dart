import 'dart:async';

import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'local_terminal_ai_managed_model_service.dart';
import 'local_terminal_ai_platform_service.dart';
import 'local_terminal_ai_settings_service.dart';

/// A single command suggestion produced by the on-device AI assistant.
class LocalTerminalAiSuggestion {
  /// Creates a new [LocalTerminalAiSuggestion].
  const LocalTerminalAiSuggestion({
    required this.command,
    required this.explanation,
  });

  /// The terminal command to offer to the user.
  final String command;

  /// Brief explanation for the command.
  final String explanation;
}

/// A suffix completion produced for the current terminal line.
class LocalTerminalAiCompletion {
  /// Creates a new [LocalTerminalAiCompletion].
  const LocalTerminalAiCompletion({
    required this.suffix,
    required this.preview,
  });

  /// The text that should be appended at the current cursor position.
  final String suffix;

  /// A human-readable preview shown in the UI.
  final String preview;
}

/// Exception raised when the on-device AI assistant is misconfigured.
class LocalTerminalAiConfigurationException implements Exception {
  /// Creates a new [LocalTerminalAiConfigurationException].
  const LocalTerminalAiConfigurationException(this.message);

  /// Human-readable description of the configuration problem.
  final String message;

  @override
  String toString() => message;
}

/// Provider for the on-device terminal AI assistant service.
final localTerminalAiServiceProvider = Provider<LocalTerminalAiService>(
  (ref) => LocalTerminalAiService(
    platformRuntime: ref.watch(localTerminalAiPlatformServiceProvider),
    managedModelCoordinator: ref.watch(
      localTerminalAiManagedModelProvider.notifier,
    ),
  ),
);

/// Service wrapping the local model runtime used for terminal assistance.
class LocalTerminalAiService {
  /// Creates a new [LocalTerminalAiService].
  LocalTerminalAiService({
    required this.platformRuntime,
    required LocalTerminalAiManagedModelCoordinator managedModelCoordinator,
    LocalTerminalAiFallbackRuntime? fallbackRuntime,
  }) : _managedModelCoordinator = managedModelCoordinator,
       _fallbackRuntime =
           fallbackRuntime ?? FlutterGemmaLocalTerminalAiFallbackRuntime();

  /// Native platform runtime bridge used when the OS exposes a built-in model.
  final LocalTerminalAiPlatformService platformRuntime;

  final LocalTerminalAiManagedModelCoordinator _managedModelCoordinator;

  final LocalTerminalAiFallbackRuntime _fallbackRuntime;

  /// Generates shell command suggestions for a user-described task.
  Future<List<LocalTerminalAiSuggestion>> suggestCommands({
    required LocalTerminalAiSettings settings,
    required String taskDescription,
    required String hostLabel,
    String? workingDirectoryPath,
    String? currentTerminalLine,
  }) async {
    final trimmedTask = taskDescription.trim();
    if (trimmedTask.isEmpty) {
      throw const LocalTerminalAiConfigurationException(
        'Describe what you want to do before asking the model for commands.',
      );
    }

    final response = await _runPrompt(
      settings: settings,
      prompt: _buildSuggestionPrompt(
        taskDescription: trimmedTask,
        hostLabel: hostLabel,
        workingDirectoryPath: workingDirectoryPath,
        currentTerminalLine: currentTerminalLine,
      ),
      maxTokens: 1024,
    );
    return _parseSuggestions(response);
  }

  /// Completes the current terminal line by returning only the missing suffix.
  Future<LocalTerminalAiCompletion> completeCurrentCommand({
    required LocalTerminalAiSettings settings,
    required String currentTerminalLine,
    required String hostLabel,
    String? workingDirectoryPath,
  }) async {
    final trimmedLine = currentTerminalLine.trimRight();
    if (trimmedLine.isEmpty) {
      throw const LocalTerminalAiConfigurationException(
        'Type part of a command before asking the model to complete it.',
      );
    }

    final response = await _runPrompt(
      settings: settings,
      prompt: _buildCompletionPrompt(
        currentTerminalLine: trimmedLine,
        hostLabel: hostLabel,
        workingDirectoryPath: workingDirectoryPath,
      ),
      maxTokens: 768,
    );

    final suffix = _normalizeCompletionSuffix(
      currentTerminalLine: trimmedLine,
      response: response,
    );
    if (suffix.isEmpty) {
      throw const LocalTerminalAiConfigurationException(
        'The model could not find a useful completion for the current line.',
      );
    }

    return LocalTerminalAiCompletion(
      suffix: suffix,
      preview: '$trimmedLine$suffix',
    );
  }

  Future<String> _runPrompt({
    required LocalTerminalAiSettings settings,
    required String prompt,
    required int maxTokens,
  }) async {
    if (!settings.enabled) {
      throw const LocalTerminalAiConfigurationException(
        'Enable the on-device terminal assistant in Settings first.',
      );
    }

    final runtimeInfo = await platformRuntime.getRuntimeInfo();
    String? nativeRuntimeFailure;
    if (runtimeInfo.shouldAttemptNativeRuntime) {
      try {
        return await platformRuntime.generateText(
          prompt: prompt,
          maxTokens: _nativeMaxTokensForRuntime(
            runtimeInfo: runtimeInfo,
            requestedMaxTokens: maxTokens,
          ),
        );
      } on LocalTerminalAiPlatformException catch (error) {
        nativeRuntimeFailure = error.message;
        if (runtimeInfo.canUseNativeRuntime) {
          throw LocalTerminalAiConfigurationException(nativeRuntimeFailure);
        }
      }
    }

    LocalTerminalAiManagedModelSpec? managedModel;
    try {
      managedModel = await _managedModelCoordinator.ensureReadyFor(settings);
    } on Exception catch (error) {
      throw LocalTerminalAiConfigurationException(error.toString());
    }
    if (managedModel != null) {
      try {
        return await _fallbackRuntime.generateText(
          prompt: prompt,
          maxTokens: maxTokens,
          managedModel: managedModel,
        );
      } on Exception catch (error) {
        throw LocalTerminalAiConfigurationException(
          _formatManagedRuntimeError(error, managedModel),
        );
      }
    }

    if (nativeRuntimeFailure != null) {
      throw LocalTerminalAiConfigurationException(nativeRuntimeFailure);
    }

    throw LocalTerminalAiConfigurationException(
      '${runtimeInfo.statusMessage} Gemma 4 download is not available on this platform.',
    );
  }

  String _buildSuggestionPrompt({
    required String taskDescription,
    required String hostLabel,
    String? workingDirectoryPath,
    String? currentTerminalLine,
  }) {
    final workingDirectory = _promptValueOrFallback(
      workingDirectoryPath,
      fallback: 'unknown',
    );
    final currentLine = _promptValueOrFallback(
      currentTerminalLine,
      fallback: 'empty',
    );
    final buffer = StringBuffer()
      ..writeln('You are an on-device terminal assistant inside an SSH client.')
      ..writeln('Suggest concise shell commands for the user request.')
      ..writeln('Keep the answer safe and practical.')
      ..writeln('Return at most three suggestions.')
      ..writeln(
        'Output format: one suggestion per line as COMMAND || short explanation.',
      )
      ..writeln('Do not use bullets, numbering, markdown, or code fences.')
      ..writeln(
        'Prefer a single command over chained shell commands when possible.',
      )
      ..writeln('If nothing is appropriate, return exactly NO_SUGGESTION.')
      ..writeln()
      ..writeln('Host: $hostLabel')
      ..writeln('Working directory: $workingDirectory')
      ..writeln('Current terminal line: $currentLine')
      ..writeln('User request: $taskDescription');
    return buffer.toString();
  }

  String _buildCompletionPrompt({
    required String currentTerminalLine,
    required String hostLabel,
    String? workingDirectoryPath,
  }) {
    final workingDirectory = _promptValueOrFallback(
      workingDirectoryPath,
      fallback: 'unknown',
    );
    final buffer = StringBuffer()
      ..writeln('You are an on-device terminal assistant inside an SSH client.')
      ..writeln(
        'Complete the current terminal line by returning only the text that should be appended after the current cursor position.',
      )
      ..writeln('Do not repeat existing text from the line.')
      ..writeln('Do not add markdown, quotes, or explanation.')
      ..writeln('Keep the completion on a single line.')
      ..writeln('If no useful completion exists, return exactly NO_COMPLETION.')
      ..writeln()
      ..writeln('Host: $hostLabel')
      ..writeln('Working directory: $workingDirectory')
      ..writeln('Current terminal line: $currentTerminalLine');
    return buffer.toString();
  }

  String _promptValueOrFallback(String? value, {required String fallback}) {
    final trimmedValue = value?.trim();
    return trimmedValue?.isNotEmpty ?? false ? trimmedValue! : fallback;
  }

  List<LocalTerminalAiSuggestion> _parseSuggestions(String response) {
    final normalizedResponse = response.trim();
    if (normalizedResponse == 'NO_SUGGESTION') {
      return const <LocalTerminalAiSuggestion>[];
    }

    final suggestions = <LocalTerminalAiSuggestion>[];
    for (final rawLine in normalizedResponse.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) {
        continue;
      }

      final parts = line.split('||');
      final command = parts.first.trim();
      if (command.isEmpty) {
        continue;
      }

      final explanation = parts.length > 1
          ? parts.sublist(1).join('||').trim()
          : 'Suggested by the on-device model.';
      suggestions.add(
        LocalTerminalAiSuggestion(command: command, explanation: explanation),
      );
      if (suggestions.length == 3) {
        break;
      }
    }

    if (suggestions.isEmpty) {
      throw const LocalTerminalAiConfigurationException(
        'The local model returned an unexpected response. Try a different model family or file.',
      );
    }

    return suggestions;
  }

  String _normalizeCompletionSuffix({
    required String currentTerminalLine,
    required String response,
  }) {
    final firstLine = response.replaceAll('\r', '').split('\n').first;
    if (firstLine.trim() == 'NO_COMPLETION') {
      return '';
    }
    if (firstLine.startsWith(currentTerminalLine)) {
      return firstLine.substring(currentTerminalLine.length);
    }
    return firstLine;
  }

  int _nativeMaxTokensForRuntime({
    required LocalTerminalAiRuntimeInfo runtimeInfo,
    required int requestedMaxTokens,
  }) {
    if (runtimeInfo.provider == LocalTerminalAiPlatformProvider.androidAiCore) {
      return requestedMaxTokens.clamp(1, 256);
    }
    return requestedMaxTokens;
  }

  String _formatManagedRuntimeError(
    Object error,
    LocalTerminalAiManagedModelSpec managedModel,
  ) {
    final errorMessage = error.toString().trim();
    if (errorMessage.contains('Failed to invoke the compiled model')) {
      return 'Managed ${managedModel.displayName} is installed but could not start on this device. MonkeySSH will keep preferring the built-in runtime when it is available.';
    }
    return 'Managed ${managedModel.displayName} failed: $errorMessage';
  }
}

/// Runtime interface for a fallback app-bundled or user-provided local model.
abstract class LocalTerminalAiFallbackRuntime {
  /// Runs the prompt through the configured fallback runtime.
  Future<String> generateText({
    required String prompt,
    required int maxTokens,
    required LocalTerminalAiManagedModelSpec managedModel,
  });
}

/// `flutter_gemma`-backed fallback runtime used off the native system path.
class FlutterGemmaLocalTerminalAiFallbackRuntime
    implements LocalTerminalAiFallbackRuntime {
  String? _activeSignature;
  Future<void>? _initializationFuture;
  Future<void> _inferenceChain = Future<void>.value();

  @override
  Future<String> generateText({
    required String prompt,
    required int maxTokens,
    required LocalTerminalAiManagedModelSpec managedModel,
  }) => _serializeInference(() async {
    await _ensureInitialized();

    final signature = managedModel.signature;
    if (_activeSignature != signature || !FlutterGemma.hasActiveModel()) {
      await FlutterGemma.installModel(
            modelType: ModelType.gemmaIt,
            fileType: managedModel.fileType,
          )
          .fromNetwork(
            managedModel.url,
            foreground: managedModel.foregroundDownload,
          )
          .install();
      _activeSignature = signature;
    }

    final model = await FlutterGemma.getActiveModel(
      maxTokens: maxTokens,
      preferredBackend: managedModel.preferredBackend,
    );
    try {
      final session = await model.createSession(
        temperature: 0.2,
        topK: 30,
        topP: 0.9,
      );
      try {
        await session.addQueryChunk(Message.text(text: prompt, isUser: true));
        return (await session.getResponse()).trimRight();
      } finally {
        await session.close();
      }
    } finally {
      await model.close();
    }
  });

  Future<void> _ensureInitialized() =>
      _initializationFuture ??= FlutterGemma.initialize();

  Future<T> _serializeInference<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    final next = _inferenceChain.catchError((Object _) {}).then((_) async {
      try {
        completer.complete(await operation());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    _inferenceChain = next;
    return completer.future;
  }
}
