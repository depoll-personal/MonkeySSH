import 'dart:async';

import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'local_terminal_ai_managed_model_service.dart';
import 'local_terminal_ai_platform_service.dart';
import 'local_terminal_ai_settings_service.dart';

const _maxSuggestionTokens = 256;
const _maxCompletionTokens = 256;
const _maxTaskDescriptionPromptChars = 280;
const _maxHostLabelPromptChars = 80;
const _maxWorkingDirectoryPromptChars = 160;
const _maxCurrentTerminalLinePromptChars = 480;
const _maxShellStatusPromptChars = 48;
const _maxRecentTerminalContextPromptChars = 900;

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
    managedModelCoordinator: ref.watch(
      localTerminalAiManagedModelProvider.notifier,
    ),
    platformService: ref.watch(localTerminalAiPlatformServiceProvider),
  ),
);

/// Service wrapping the local model runtime used for terminal assistance.
class LocalTerminalAiService {
  /// Creates a new [LocalTerminalAiService].
  LocalTerminalAiService({
    required LocalTerminalAiManagedModelCoordinator managedModelCoordinator,
    LocalTerminalAiPlatformService? platformService,
    LocalTerminalAiFallbackRuntime? fallbackRuntime,
  }) : _managedModelCoordinator = managedModelCoordinator,
       _platformService =
           platformService ?? const LocalTerminalAiPlatformService(),
       _fallbackRuntime =
           fallbackRuntime ?? FlutterGemmaLocalTerminalAiFallbackRuntime();

  final LocalTerminalAiManagedModelCoordinator _managedModelCoordinator;
  final LocalTerminalAiPlatformService _platformService;

  final LocalTerminalAiFallbackRuntime _fallbackRuntime;

  /// Generates shell command suggestions for a user-described task.
  Future<List<LocalTerminalAiSuggestion>> suggestCommands({
    required LocalTerminalAiSettings settings,
    required String taskDescription,
    required String hostLabel,
    String? workingDirectoryPath,
    String? currentTerminalLine,
    String? shellStatusLabel,
    String? recentTerminalContext,
  }) async {
    final trimmedTask = taskDescription.trim();
    if (trimmedTask.isEmpty) {
      throw const LocalTerminalAiConfigurationException(
        'Describe what you want to do before asking the model for commands.',
      );
    }

    final runtimeInfo = await _platformService.getRuntimeInfo();
    final response = await _runPrompt(
      settings: settings,
      runtimeInfo: runtimeInfo,
      prompt: _buildSuggestionPrompt(
        runtimeLabel: _promptRuntimeLabel(runtimeInfo),
        taskDescription: trimmedTask,
        hostLabel: hostLabel,
        workingDirectoryPath: workingDirectoryPath,
        currentTerminalLine: currentTerminalLine,
        shellStatusLabel: shellStatusLabel,
        recentTerminalContext: recentTerminalContext,
      ),
      maxTokens: _maxSuggestionTokens,
    );
    return _parseSuggestions(response);
  }

  /// Completes the current terminal line by returning only the missing suffix.
  Future<LocalTerminalAiCompletion> completeCurrentCommand({
    required LocalTerminalAiSettings settings,
    required String currentTerminalLine,
    required String hostLabel,
    String? workingDirectoryPath,
    String? shellStatusLabel,
    String? recentTerminalContext,
  }) async {
    final trimmedLine = currentTerminalLine.trimRight();
    if (trimmedLine.isEmpty) {
      throw const LocalTerminalAiConfigurationException(
        'Type part of a command before asking the model to complete it.',
      );
    }

    final runtimeInfo = await _platformService.getRuntimeInfo();
    final response = await _runPrompt(
      settings: settings,
      runtimeInfo: runtimeInfo,
      prompt: _buildCompletionPrompt(
        runtimeLabel: _promptRuntimeLabel(runtimeInfo),
        currentTerminalLine: trimmedLine,
        hostLabel: hostLabel,
        workingDirectoryPath: workingDirectoryPath,
        shellStatusLabel: shellStatusLabel,
        recentTerminalContext: recentTerminalContext,
      ),
      maxTokens: _maxCompletionTokens,
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
    required LocalTerminalAiRuntimeInfo runtimeInfo,
    required String prompt,
    required int maxTokens,
  }) async {
    if (!settings.enabled) {
      throw const LocalTerminalAiConfigurationException(
        'Enable the on-device terminal assistant in Settings first.',
      );
    }

    if (runtimeInfo.shouldAttemptNativeRuntime) {
      return _runNativePrompt(
        runtimeInfo: runtimeInfo,
        prompt: prompt,
        maxTokens: maxTokens,
      );
    }

    LocalTerminalAiManagedModelSpec? managedModel;
    try {
      managedModel = await _managedModelCoordinator.ensureReadyFor(settings);
    } on Exception catch (error) {
      throw LocalTerminalAiConfigurationException(
        _formatManagedModelSetupError(error),
      );
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

    throw LocalTerminalAiConfigurationException(runtimeInfo.statusMessage);
  }

  Future<String> _runNativePrompt({
    required LocalTerminalAiRuntimeInfo runtimeInfo,
    required String prompt,
    required int maxTokens,
  }) async {
    if (runtimeInfo.provider ==
            LocalTerminalAiPlatformProvider.appleFoundationModels &&
        !runtimeInfo.available) {
      throw LocalTerminalAiConfigurationException(runtimeInfo.statusMessage);
    }

    try {
      if (runtimeInfo.provider ==
              LocalTerminalAiPlatformProvider.androidAiCore &&
          !runtimeInfo.available) {
        await _platformService.prepareRuntime();
      }
      return await _platformService.generateText(
        prompt: prompt,
        maxTokens: maxTokens,
      );
    } on LocalTerminalAiPlatformException catch (error) {
      final trimmedMessage = error.message.trim();
      throw LocalTerminalAiConfigurationException(
        trimmedMessage.isNotEmpty ? trimmedMessage : runtimeInfo.statusMessage,
      );
    }
  }

  String _buildSuggestionPrompt({
    required String runtimeLabel,
    required String taskDescription,
    required String hostLabel,
    String? workingDirectoryPath,
    String? currentTerminalLine,
    String? shellStatusLabel,
    String? recentTerminalContext,
  }) {
    final normalizedTaskDescription = _normalizePromptText(
      taskDescription,
      maxChars: _maxTaskDescriptionPromptChars,
    );
    final normalizedHostLabel = _normalizePromptText(
      hostLabel,
      maxChars: _maxHostLabelPromptChars,
    );
    final workingDirectory = _promptValueOrFallback(
      workingDirectoryPath,
      fallback: 'unknown',
      maxChars: _maxWorkingDirectoryPromptChars,
    );
    final currentLine = _promptValueOrFallback(
      currentTerminalLine,
      fallback: 'empty',
      maxChars: _maxCurrentTerminalLinePromptChars,
      preferTail: true,
    );
    final shellStatus = _promptValueOrFallback(
      shellStatusLabel,
      fallback: 'unknown',
      maxChars: _maxShellStatusPromptChars,
    );
    final terminalContext = _promptValueOrFallback(
      recentTerminalContext,
      fallback: 'none',
      maxChars: _maxRecentTerminalContextPromptChars,
      preferTail: true,
    );
    final buffer = StringBuffer()
      ..writeln('You are an on-device terminal assistant inside an SSH client.')
      ..writeln(
        'You are running on a small on-device model, so use only the highest-value context below.',
      )
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
      ..writeln(
        'Do not invent remote platform details that are not present in the context.',
      )
      ..writeln('If nothing is appropriate, return exactly NO_SUGGESTION.')
      ..writeln()
      ..writeln('Local runtime: $runtimeLabel')
      ..writeln('Host: $normalizedHostLabel')
      ..writeln('Shell status: $shellStatus')
      ..writeln('Working directory: $workingDirectory')
      ..writeln('Current terminal line: $currentLine')
      ..writeln('Recent terminal context:')
      ..writeln(terminalContext)
      ..writeln('User request: $normalizedTaskDescription');
    return buffer.toString();
  }

  String _buildCompletionPrompt({
    required String runtimeLabel,
    required String currentTerminalLine,
    required String hostLabel,
    String? workingDirectoryPath,
    String? shellStatusLabel,
    String? recentTerminalContext,
  }) {
    final normalizedHostLabel = _normalizePromptText(
      hostLabel,
      maxChars: _maxHostLabelPromptChars,
    );
    final normalizedCurrentLine = _normalizePromptText(
      currentTerminalLine,
      maxChars: _maxCurrentTerminalLinePromptChars,
      preferTail: true,
    );
    final workingDirectory = _promptValueOrFallback(
      workingDirectoryPath,
      fallback: 'unknown',
      maxChars: _maxWorkingDirectoryPromptChars,
    );
    final shellStatus = _promptValueOrFallback(
      shellStatusLabel,
      fallback: 'unknown',
      maxChars: _maxShellStatusPromptChars,
    );
    final terminalContext = _promptValueOrFallback(
      recentTerminalContext,
      fallback: 'none',
      maxChars: _maxRecentTerminalContextPromptChars,
      preferTail: true,
    );
    final buffer = StringBuffer()
      ..writeln('You are an on-device terminal assistant inside an SSH client.')
      ..writeln(
        'You are running on a small on-device model, so focus on the current line and the freshest terminal context.',
      )
      ..writeln(
        'Complete the current terminal line by returning only the text that should be appended after the current cursor position.',
      )
      ..writeln('Do not repeat existing text from the line.')
      ..writeln('Do not add markdown, quotes, or explanation.')
      ..writeln('Keep the completion on a single line.')
      ..writeln(
        'Do not invent remote platform details that are not present in the context.',
      )
      ..writeln('If no useful completion exists, return exactly NO_COMPLETION.')
      ..writeln()
      ..writeln('Local runtime: $runtimeLabel')
      ..writeln('Host: $normalizedHostLabel')
      ..writeln('Shell status: $shellStatus')
      ..writeln('Working directory: $workingDirectory')
      ..writeln('Recent terminal context:')
      ..writeln(terminalContext)
      ..writeln('Current terminal line: $normalizedCurrentLine');
    return buffer.toString();
  }

  String _promptRuntimeLabel(LocalTerminalAiRuntimeInfo runtimeInfo) {
    if (runtimeInfo.provider == LocalTerminalAiPlatformProvider.none) {
      return 'Managed Gemma 4';
    }
    final modelName = runtimeInfo.modelName?.trim();
    if (modelName case final String modelName when modelName.isNotEmpty) {
      return '${runtimeInfo.providerLabel} ($modelName)';
    }
    return runtimeInfo.providerLabel;
  }

  String _promptValueOrFallback(
    String? value, {
    required String fallback,
    required int maxChars,
    bool preferTail = false,
  }) {
    final trimmedValue = value?.trim();
    return trimmedValue?.isNotEmpty ?? false
        ? _normalizePromptText(
            trimmedValue!,
            maxChars: maxChars,
            preferTail: preferTail,
          )
        : fallback;
  }

  String _normalizePromptText(
    String value, {
    required int maxChars,
    bool preferTail = false,
  }) {
    final normalized = value
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .trim();
    if (normalized.length <= maxChars) {
      return normalized;
    }
    if (maxChars <= 3) {
      return normalized.substring(0, maxChars);
    }
    return preferTail
        ? '...${normalized.substring(normalized.length - (maxChars - 3))}'
        : '${normalized.substring(0, maxChars - 3)}...';
  }

  String _formatManagedModelSetupError(Object error) {
    final errorMessage = error.toString();
    const exceptionPrefix = 'Exception: ';
    if (errorMessage.startsWith(exceptionPrefix)) {
      return errorMessage.substring(exceptionPrefix.length);
    }
    return errorMessage;
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
        'The local model returned an unexpected response. Try again.',
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

  String _formatManagedRuntimeError(
    Object error,
    LocalTerminalAiManagedModelSpec managedModel,
  ) {
    final errorMessage = error.toString().trim();
    if (isManagedGemmaRuntimeStartupError(error)) {
      return 'Managed ${managedModel.displayName} is installed but could not start on this device. Reinstall it from Settings and try again.';
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
  Future<void>? _initializationFuture;
  Future<void> _inferenceChain = Future<void>.value();

  @override
  Future<String> generateText({
    required String prompt,
    required int maxTokens,
    required LocalTerminalAiManagedModelSpec managedModel,
  }) => _serializeInference(() async {
    await _ensureInitialized();

    if (!FlutterGemma.hasActiveModel()) {
      await FlutterGemma.installModel(
            modelType: ModelType.gemmaIt,
            fileType: managedModel.fileType,
          )
          .fromNetwork(
            managedModel.url,
            foreground: managedModel.foregroundDownload,
          )
          .install();
    }

    return runWithManagedGemmaBackendFallback(
      spec: managedModel,
      operation: (preferredBackend) async {
        final model = await FlutterGemma.getActiveModel(
          maxTokens: maxTokens,
          preferredBackend: preferredBackend,
        );
        try {
          final session = await createManagedGemmaInferenceSession(model);
          try {
            await session.addQueryChunk(
              Message.text(text: prompt, isUser: true),
            );
            return (await session.getResponse()).trimRight();
          } finally {
            await session.close();
          }
        } finally {
          await model.close();
        }
      },
    );
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
