import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  ),
);

/// Service wrapping the local model runtime used for terminal assistance.
class LocalTerminalAiService {
  /// Creates a new [LocalTerminalAiService].
  LocalTerminalAiService({
    required this.platformRuntime,
    LocalTerminalAiFallbackRuntime? fallbackRuntime,
  }) : _fallbackRuntime =
           fallbackRuntime ?? FlutterGemmaLocalTerminalAiFallbackRuntime();

  /// Native platform runtime bridge used when the OS exposes a built-in model.
  final LocalTerminalAiPlatformService platformRuntime;

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
    if (settings.preferNativeRuntime && runtimeInfo.canUseNativeRuntime) {
      return platformRuntime.generateText(prompt: prompt, maxTokens: maxTokens);
    }

    if (settings.hasConfiguredFallbackModel) {
      return _fallbackRuntime.generateText(
        settings: settings,
        prompt: prompt,
        maxTokens: maxTokens,
      );
    }

    if (settings.preferNativeRuntime) {
      throw LocalTerminalAiConfigurationException(
        '${runtimeInfo.statusMessage} Select a local `.task` or `.litertlm` '
        'model file in Settings to use the fallback runtime.',
      );
    }

    throw const LocalTerminalAiConfigurationException(
      'Select a local `.task` or `.litertlm` model file in Settings '
      'before using the fallback runtime.',
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
}

/// Runtime interface for a fallback app-bundled or user-provided local model.
abstract class LocalTerminalAiFallbackRuntime {
  /// Runs the prompt through the configured fallback runtime.
  Future<String> generateText({
    required LocalTerminalAiSettings settings,
    required String prompt,
    required int maxTokens,
  });
}

/// `flutter_gemma`-backed fallback runtime used off the native system path.
class FlutterGemmaLocalTerminalAiFallbackRuntime
    implements LocalTerminalAiFallbackRuntime {
  String? _activeSignature;

  @override
  Future<String> generateText({
    required LocalTerminalAiSettings settings,
    required String prompt,
    required int maxTokens,
  }) async {
    final fileType = settings.inferredFileType;
    final modelPath = settings.modelPath;
    if (modelPath == null || modelPath.trim().isEmpty) {
      throw const LocalTerminalAiConfigurationException(
        'Select a local `.task` or `.litertlm` model file in Settings.',
      );
    }
    if (fileType == null) {
      throw const LocalTerminalAiConfigurationException(
        'Unsupported model file. Use a `.task` file on mobile or `.litertlm` on desktop.',
      );
    }

    final signature = settings.signature;
    if (_activeSignature != signature || !FlutterGemma.hasActiveModel()) {
      await FlutterGemma.installModel(
        modelType: settings.modelType,
        fileType: fileType,
      ).fromFile(modelPath).install();
      _activeSignature = signature;
    }

    final model = await FlutterGemma.getActiveModel(maxTokens: maxTokens);
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
  }
}
