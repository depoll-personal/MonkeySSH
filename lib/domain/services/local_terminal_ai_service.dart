import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'local_terminal_ai_managed_model_service.dart';
import 'local_terminal_ai_platform_service.dart';
import 'local_terminal_ai_settings_service.dart';

const _unexpectedSuggestionResponseMessage =
    'The local model returned an unexpected response. Try again.';
final _suggestionListPrefixPattern = RegExp(r'^(?:[-*•]+|\d+[.)])\s*');
final _suggestionBacktickPattern = RegExp('`([^`]+)`');
final _suggestionWhitespacePattern = RegExp(r'\s+');
final _shellSyntaxCharacterPattern = RegExp(r"""[|&;<>()$`'"\\[\]{}=*?]""");
final _simpleShellTokenPattern = RegExp(r'^[-./~:@%+,=\w]+$');
const _managedPromptBudget = _LocalTerminalAiPromptBudget(
  maxSuggestionTokens: 512,
  maxCompletionTokens: 512,
  maxTaskDescriptionChars: 480,
  maxHostLabelChars: 120,
  maxWindowTitleChars: 160,
  maxWindowIconChars: 80,
  maxConnectionStateChars: 48,
  maxWorkingDirectoryChars: 240,
  maxCurrentTerminalLineChars: 960,
  maxShellStatusChars: 64,
  maxSelectedTerminalTextChars: 900,
  maxRecentTerminalContextChars: 2400,
);
const _androidManagedPromptBudget = _LocalTerminalAiPromptBudget(
  maxSuggestionTokens: 512,
  maxCompletionTokens: 512,
  maxTaskDescriptionChars: 480,
  maxHostLabelChars: 120,
  maxWindowTitleChars: 120,
  maxWindowIconChars: 60,
  maxConnectionStateChars: 48,
  maxWorkingDirectoryChars: 200,
  maxCurrentTerminalLineChars: 640,
  maxShellStatusChars: 64,
  maxSelectedTerminalTextChars: 600,
  maxRecentTerminalContextChars: 1600,
);
const _nativePromptBudget = _LocalTerminalAiPromptBudget(
  maxSuggestionTokens: 256,
  maxCompletionTokens: 256,
  maxTaskDescriptionChars: 280,
  maxHostLabelChars: 80,
  maxWindowTitleChars: 80,
  maxWindowIconChars: 40,
  maxConnectionStateChars: 32,
  maxWorkingDirectoryChars: 160,
  maxCurrentTerminalLineChars: 480,
  maxShellStatusChars: 48,
  maxSelectedTerminalTextChars: 360,
  maxRecentTerminalContextChars: 900,
);
const _placeholderSuggestionCommands = <String>{
  'command',
  'shell command',
  'example command',
  'sample command',
  'command here',
  'your command',
  'your command here',
};
const _placeholderSuggestionExplanations = <String>{
  'short explanation',
  'brief explanation',
  'explanation',
  'reason',
  'details',
  'description',
};
const _descriptionLikeLeadingWords = <String>{
  'check',
  'display',
  'find',
  'get',
  'inspect',
  'list',
  'print',
  'review',
  'show',
  'view',
};

/// Snapshot of the terminal session and visible screen state used for prompts.
@immutable
class LocalTerminalAiPromptContext {
  /// Creates a new [LocalTerminalAiPromptContext].
  const LocalTerminalAiPromptContext({
    required this.hostLabel,
    this.currentTerminalLine,
    this.shellStatusLabel,
    this.recentTerminalContext,
    this.workingDirectoryPath,
    this.windowTitle,
    this.windowIconLabel,
    this.connectionStateLabel,
    this.selectedTerminalText,
    this.usingAlternateScreen = false,
    this.terminalColumns,
    this.terminalRows,
  });

  /// Host label shown for the active terminal tab.
  final String hostLabel;

  /// Current wrapped terminal line at the cursor, if any.
  final String? currentTerminalLine;

  /// Current shell lifecycle state label, if available.
  final String? shellStatusLabel;

  /// Recent terminal text around the active prompt or cursor.
  final String? recentTerminalContext;

  /// Current working directory reported by shell integration.
  final String? workingDirectoryPath;

  /// Current terminal window title reported by the remote shell/app.
  final String? windowTitle;

  /// Current icon or mode label reported by the terminal session.
  final String? windowIconLabel;

  /// Human-readable SSH connection state for the session.
  final String? connectionStateLabel;

  /// Selected text the user is currently focusing on, if any.
  final String? selectedTerminalText;

  /// Whether the terminal is currently showing the alternate screen buffer.
  final bool usingAlternateScreen;

  /// Current terminal viewport column count.
  final int? terminalColumns;

  /// Current terminal viewport row count.
  final int? terminalRows;
}

class _LocalTerminalAiPromptBudget {
  const _LocalTerminalAiPromptBudget({
    required this.maxSuggestionTokens,
    required this.maxCompletionTokens,
    required this.maxTaskDescriptionChars,
    required this.maxHostLabelChars,
    required this.maxWindowTitleChars,
    required this.maxWindowIconChars,
    required this.maxConnectionStateChars,
    required this.maxWorkingDirectoryChars,
    required this.maxCurrentTerminalLineChars,
    required this.maxShellStatusChars,
    required this.maxSelectedTerminalTextChars,
    required this.maxRecentTerminalContextChars,
  });

  final int maxSuggestionTokens;
  final int maxCompletionTokens;
  final int maxTaskDescriptionChars;
  final int maxHostLabelChars;
  final int maxWindowTitleChars;
  final int maxWindowIconChars;
  final int maxConnectionStateChars;
  final int maxWorkingDirectoryChars;
  final int maxCurrentTerminalLineChars;
  final int maxShellStatusChars;
  final int maxSelectedTerminalTextChars;
  final int maxRecentTerminalContextChars;
}

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
    required LocalTerminalAiPromptContext promptContext,
  }) async {
    final trimmedTask = taskDescription.trim();
    if (trimmedTask.isEmpty) {
      throw const LocalTerminalAiConfigurationException(
        'Describe what you want to do before asking the model for commands.',
      );
    }

    final preferredManagedModel = localTerminalAiManagedModelSpecForSettings(
      settings,
    );
    final useCompactManagedPrompt = _shouldUseCompactManagedPrompt(
      preferredManagedModel: preferredManagedModel,
    );
    final promptBudget = _promptBudgetFor(
      preferredManagedModel: preferredManagedModel,
    );
    final runtimeInfo = await _platformService.getRuntimeInfo();
    final response = await _runPrompt(
      settings: settings,
      runtimeInfo: runtimeInfo,
      preferredManagedModel: preferredManagedModel,
      prompt: useCompactManagedPrompt
          ? _buildCompactSuggestionPrompt(
              promptBudget: promptBudget,
              runtimeLabel: _promptRuntimeLabel(
                runtimeInfo,
                preferredManagedModel: preferredManagedModel,
              ),
              taskDescription: trimmedTask,
              promptContext: promptContext,
            )
          : _buildSuggestionPrompt(
              promptBudget: promptBudget,
              runtimeLabel: _promptRuntimeLabel(
                runtimeInfo,
                preferredManagedModel: preferredManagedModel,
              ),
              taskDescription: trimmedTask,
              promptContext: promptContext,
            ),
      maxTokens: promptBudget.maxSuggestionTokens,
    );
    return _parseSuggestions(response);
  }

  /// Completes the current terminal line by returning only the missing suffix.
  Future<LocalTerminalAiCompletion> completeCurrentCommand({
    required LocalTerminalAiSettings settings,
    required String currentTerminalLine,
    required LocalTerminalAiPromptContext promptContext,
  }) async {
    final trimmedLine = currentTerminalLine.trimRight();
    if (trimmedLine.isEmpty) {
      throw const LocalTerminalAiConfigurationException(
        'Type part of a command before asking the model to complete it.',
      );
    }

    final preferredManagedModel = localTerminalAiManagedModelSpecForSettings(
      settings,
    );
    final useCompactManagedPrompt = _shouldUseCompactManagedPrompt(
      preferredManagedModel: preferredManagedModel,
    );
    final promptBudget = _promptBudgetFor(
      preferredManagedModel: preferredManagedModel,
    );
    final runtimeInfo = await _platformService.getRuntimeInfo();
    final response = await _runPrompt(
      settings: settings,
      runtimeInfo: runtimeInfo,
      preferredManagedModel: preferredManagedModel,
      prompt: useCompactManagedPrompt
          ? _buildCompactCompletionPrompt(
              promptBudget: promptBudget,
              runtimeLabel: _promptRuntimeLabel(
                runtimeInfo,
                preferredManagedModel: preferredManagedModel,
              ),
              currentTerminalLine: trimmedLine,
              promptContext: promptContext,
            )
          : _buildCompletionPrompt(
              promptBudget: promptBudget,
              runtimeLabel: _promptRuntimeLabel(
                runtimeInfo,
                preferredManagedModel: preferredManagedModel,
              ),
              currentTerminalLine: trimmedLine,
              promptContext: promptContext,
            ),
      maxTokens: promptBudget.maxCompletionTokens,
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
    required LocalTerminalAiManagedModelSpec? preferredManagedModel,
    required String prompt,
    required int maxTokens,
  }) async {
    if (!settings.enabled) {
      throw const LocalTerminalAiConfigurationException(
        'Enable the on-device terminal assistant in Settings first.',
      );
    }

    if (preferredManagedModel != null) {
      try {
        final managedModel = await _managedModelCoordinator.ensureReadyFor(
          settings,
        );
        if (managedModel == null) {
          throw LocalTerminalAiConfigurationException(
            'Managed ${preferredManagedModel.displayName} is not ready on this device yet.',
          );
        }
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
      } on LocalTerminalAiConfigurationException {
        rethrow;
      } on Exception catch (error) {
        throw LocalTerminalAiConfigurationException(
          _formatManagedModelSetupError(error),
        );
      }
    }

    if (runtimeInfo.shouldAttemptNativeRuntime) {
      return _runNativePrompt(
        runtimeInfo: runtimeInfo,
        prompt: prompt,
        maxTokens: maxTokens,
      );
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
    required _LocalTerminalAiPromptBudget promptBudget,
    required String runtimeLabel,
    required String taskDescription,
    required LocalTerminalAiPromptContext promptContext,
  }) {
    final normalizedTaskDescription = _normalizePromptText(
      taskDescription,
      maxChars: promptBudget.maxTaskDescriptionChars,
    );
    final buffer = StringBuffer()
      ..writeln('You are an on-device terminal assistant inside an SSH client.')
      ..writeln(
        'Use the structured terminal context below to suggest shell commands that match what the user is looking at right now.',
      )
      ..writeln('Suggest concise shell commands for the user request.')
      ..writeln('Keep the answer safe and practical.')
      ..writeln('Return at most three suggestions.')
      ..writeln(
        'Output format: one suggestion per line as CMD: <actual shell command> || WHY: <short explanation>.',
      )
      ..writeln(
        'Example: CMD: ls -la || WHY: List files in the current directory with details.',
      )
      ..writeln(
        'Do not use bullets, numbering, markdown, code fences, or extra prose.',
      )
      ..writeln(
        'Never output placeholders like COMMAND or short explanation, and never describe a command instead of writing it.',
      )
      ..writeln(
        'If selected text is present, treat it as the user\'s focus. If the visible terminal context shows logs, errors, or file output, prefer commands that build on that context.',
      )
      ..writeln(
        'Prefer a single command over chained shell commands when possible.',
      )
      ..writeln(
        'Do not invent remote platform details that are not present in the context.',
      )
      ..writeln('If nothing is appropriate, return exactly NO_SUGGESTION.')
      ..writeln()
      ..writeln('<terminal_context>')
      ..writeln('runtime: $runtimeLabel');
    _appendPromptContext(
      buffer,
      promptContext,
      promptBudget: promptBudget,
      includeCurrentTerminalLine: true,
    );
    buffer
      ..writeln('</terminal_context>')
      ..writeln('<user_request>')
      ..writeln(normalizedTaskDescription)
      ..writeln('</user_request>');
    return buffer.toString();
  }

  String _buildCompletionPrompt({
    required _LocalTerminalAiPromptBudget promptBudget,
    required String runtimeLabel,
    required String currentTerminalLine,
    required LocalTerminalAiPromptContext promptContext,
  }) {
    final normalizedCurrentLine = _normalizePromptText(
      currentTerminalLine,
      maxChars: promptBudget.maxCurrentTerminalLineChars,
      preferTail: true,
    );
    final buffer = StringBuffer()
      ..writeln('You are an on-device terminal assistant inside an SSH client.')
      ..writeln(
        'Use the structured terminal context below to complete the current terminal line.',
      )
      ..writeln(
        'Complete the current terminal line by returning only the text that should be appended after the current cursor position.',
      )
      ..writeln(
        'Return the shortest useful suffix that fits the current context.',
      )
      ..writeln('Output format: APPEND: <suffix>')
      ..writeln('Do not repeat existing text from the line.')
      ..writeln(
        'Do not add markdown, quotes, explanation, or the full command.',
      )
      ..writeln('Keep the completion on a single line.')
      ..writeln(
        'Do not invent remote platform details that are not present in the context.',
      )
      ..writeln('If no useful completion exists, return exactly NO_COMPLETION.')
      ..writeln()
      ..writeln('<terminal_context>')
      ..writeln('runtime: $runtimeLabel');
    _appendPromptContext(
      buffer,
      promptContext,
      promptBudget: promptBudget,
      includeCurrentTerminalLine: false,
    );
    buffer
      ..writeln('current_terminal_line: $normalizedCurrentLine')
      ..writeln('</terminal_context>');
    return buffer.toString();
  }

  String _buildCompactSuggestionPrompt({
    required _LocalTerminalAiPromptBudget promptBudget,
    required String runtimeLabel,
    required String taskDescription,
    required LocalTerminalAiPromptContext promptContext,
  }) {
    final normalizedTaskDescription = _normalizePromptText(
      taskDescription,
      maxChars: promptBudget.maxTaskDescriptionChars,
    );
    final buffer = StringBuffer()
      ..writeln(
        'Suggest up to 3 safe shell commands for this SSH terminal task.',
      )
      ..writeln('Each line: CMD: <command> || WHY: <short reason>')
      ..writeln('No bullets, markdown, or extra prose. If none: NO_SUGGESTION.')
      ..writeln(
        'Use selected_text first, then current_line, then visible_context.',
      )
      ..writeln('Use only facts below.')
      ..writeln('ctx{');
    _appendCompactPromptContext(
      buffer,
      promptContext,
      promptBudget: promptBudget,
      runtimeLabel: runtimeLabel,
      includeCurrentTerminalLine: true,
    );
    buffer
      ..writeln('}')
      ..writeln('task{$normalizedTaskDescription}');
    return buffer.toString();
  }

  String _buildCompactCompletionPrompt({
    required _LocalTerminalAiPromptBudget promptBudget,
    required String runtimeLabel,
    required String currentTerminalLine,
    required LocalTerminalAiPromptContext promptContext,
  }) {
    final normalizedCurrentLine = _normalizePromptText(
      currentTerminalLine,
      maxChars: promptBudget.maxCurrentTerminalLineChars,
      preferTail: true,
    );
    final buffer = StringBuffer()
      ..writeln('Complete this SSH terminal line.')
      ..writeln('Return one line only: APPEND: <suffix>')
      ..writeln('No quotes, explanation, markdown, or full command.')
      ..writeln('If none: NO_COMPLETION.')
      ..writeln('Use only facts below.')
      ..writeln('ctx{');
    _appendCompactPromptContext(
      buffer,
      promptContext,
      promptBudget: promptBudget,
      runtimeLabel: runtimeLabel,
      includeCurrentTerminalLine: false,
    );
    buffer
      ..writeln('line:$normalizedCurrentLine')
      ..writeln('}');
    return buffer.toString();
  }

  _LocalTerminalAiPromptBudget _promptBudgetFor({
    required LocalTerminalAiManagedModelSpec? preferredManagedModel,
  }) => preferredManagedModel != null
      ? (_shouldUseCompactManagedPrompt(
              preferredManagedModel: preferredManagedModel,
            )
            ? _androidManagedPromptBudget
            : _managedPromptBudget)
      : _nativePromptBudget;

  bool _shouldUseCompactManagedPrompt({
    required LocalTerminalAiManagedModelSpec? preferredManagedModel,
  }) =>
      preferredManagedModel != null &&
      defaultTargetPlatform == TargetPlatform.android;

  void _appendPromptContext(
    StringBuffer buffer,
    LocalTerminalAiPromptContext promptContext, {
    required _LocalTerminalAiPromptBudget promptBudget,
    required bool includeCurrentTerminalLine,
  }) {
    final normalizedHostLabel = _normalizePromptText(
      promptContext.hostLabel,
      maxChars: promptBudget.maxHostLabelChars,
    );
    final workingDirectory = _promptValueOrFallback(
      promptContext.workingDirectoryPath,
      fallback: 'unknown',
      maxChars: promptBudget.maxWorkingDirectoryChars,
    );
    final shellStatus = _promptValueOrFallback(
      promptContext.shellStatusLabel,
      fallback: 'unknown',
      maxChars: promptBudget.maxShellStatusChars,
    );
    final terminalContext = _promptValueOrFallback(
      promptContext.recentTerminalContext,
      fallback: 'none',
      maxChars: promptBudget.maxRecentTerminalContextChars,
      preferTail: true,
    );
    final selectedText = _promptValueOrFallback(
      promptContext.selectedTerminalText,
      fallback: 'none',
      maxChars: promptBudget.maxSelectedTerminalTextChars,
    );
    final windowTitle = _promptValueOrFallback(
      promptContext.windowTitle,
      fallback: 'none',
      maxChars: promptBudget.maxWindowTitleChars,
    );
    final windowIcon = _promptValueOrFallback(
      promptContext.windowIconLabel,
      fallback: 'none',
      maxChars: promptBudget.maxWindowIconChars,
    );
    final connectionState = _promptValueOrFallback(
      promptContext.connectionStateLabel,
      fallback: 'unknown',
      maxChars: promptBudget.maxConnectionStateChars,
    );
    final terminalSize = switch ((
      promptContext.terminalColumns,
      promptContext.terminalRows,
    )) {
      (final int columns?, final int rows?) => '$columns x $rows',
      _ => 'unknown',
    };
    buffer
      ..writeln('host: $normalizedHostLabel')
      ..writeln('connection_state: $connectionState')
      ..writeln('working_directory: $workingDirectory')
      ..writeln('shell_status: $shellStatus')
      ..writeln('window_title: $windowTitle')
      ..writeln('window_icon: $windowIcon')
      ..writeln(
        'alternate_screen: ${promptContext.usingAlternateScreen ? 'yes' : 'no'}',
      )
      ..writeln('terminal_size: $terminalSize');
    if (includeCurrentTerminalLine) {
      final currentLine = _promptValueOrFallback(
        promptContext.currentTerminalLine,
        fallback: 'empty',
        maxChars: promptBudget.maxCurrentTerminalLineChars,
        preferTail: true,
      );
      buffer.writeln('current_terminal_line: $currentLine');
    }
    buffer
      ..writeln('selected_text:')
      ..writeln(selectedText)
      ..writeln('visible_terminal_context:')
      ..writeln(terminalContext);
  }

  void _appendCompactPromptContext(
    StringBuffer buffer,
    LocalTerminalAiPromptContext promptContext, {
    required _LocalTerminalAiPromptBudget promptBudget,
    required String runtimeLabel,
    required bool includeCurrentTerminalLine,
  }) {
    final normalizedHostLabel = _normalizePromptText(
      promptContext.hostLabel,
      maxChars: promptBudget.maxHostLabelChars,
    );
    final workingDirectory = _promptValueOrFallback(
      promptContext.workingDirectoryPath,
      fallback: '-',
      maxChars: promptBudget.maxWorkingDirectoryChars,
    );
    final shellStatus = _promptValueOrFallback(
      promptContext.shellStatusLabel,
      fallback: '-',
      maxChars: promptBudget.maxShellStatusChars,
    );
    final terminalContext = _promptValueOrFallback(
      promptContext.recentTerminalContext,
      fallback: '-',
      maxChars: promptBudget.maxRecentTerminalContextChars,
      preferTail: true,
    );
    final selectedText = _promptValueOrFallback(
      promptContext.selectedTerminalText,
      fallback: '-',
      maxChars: promptBudget.maxSelectedTerminalTextChars,
      preferTail: true,
    );
    final windowTitle = _promptValueOrFallback(
      promptContext.windowTitle,
      fallback: '-',
      maxChars: promptBudget.maxWindowTitleChars,
    );
    final connectionState = _promptValueOrFallback(
      promptContext.connectionStateLabel,
      fallback: '-',
      maxChars: promptBudget.maxConnectionStateChars,
    );
    buffer
      ..writeln('rt:$runtimeLabel')
      ..writeln('host:$normalizedHostLabel')
      ..writeln('conn:$connectionState')
      ..writeln('cwd:$workingDirectory')
      ..writeln('shell:$shellStatus')
      ..writeln('win:$windowTitle')
      ..writeln('alt:${promptContext.usingAlternateScreen ? 'y' : 'n'}');
    if (includeCurrentTerminalLine) {
      final currentLine = _promptValueOrFallback(
        promptContext.currentTerminalLine,
        fallback: '-',
        maxChars: promptBudget.maxCurrentTerminalLineChars,
        preferTail: true,
      );
      buffer.writeln('line:$currentLine');
    }
    buffer
      ..writeln('sel:$selectedText')
      ..writeln('ctx:$terminalContext');
  }

  String _promptRuntimeLabel(
    LocalTerminalAiRuntimeInfo runtimeInfo, {
    required LocalTerminalAiManagedModelSpec? preferredManagedModel,
  }) {
    if (preferredManagedModel != null) {
      return 'Managed ${preferredManagedModel.displayName}';
    }
    if (runtimeInfo.provider == LocalTerminalAiPlatformProvider.none) {
      return 'Managed Gemma';
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
    String? pendingCommand;
    String? pendingExplanation;
    void flushPendingSuggestion() {
      final command = pendingCommand;
      if (command == null) {
        return;
      }
      final suggestion = _buildSuggestion(
        command: command,
        explanation: pendingExplanation,
      );
      pendingCommand = null;
      pendingExplanation = null;
      if (suggestion == null) {
        return;
      }
      suggestions.add(suggestion);
    }

    for (final rawLine in normalizedResponse.split('\n')) {
      if (_tryParseTaggedSuggestionCommand(rawLine) case (
        final String command,
        final String? explanation,
      )) {
        flushPendingSuggestion();
        pendingCommand = command;
        pendingExplanation = explanation;
        if (pendingExplanation != null) {
          flushPendingSuggestion();
        }
        if (suggestions.length == 3) {
          break;
        }
        continue;
      }
      if (_tryParseTaggedSuggestionExplanation(rawLine)
          case final String explanation?) {
        if (pendingCommand != null) {
          pendingExplanation = explanation;
          flushPendingSuggestion();
          if (suggestions.length == 3) {
            break;
          }
        }
        continue;
      }
      final suggestion = _parseSuggestionLine(rawLine);
      if (suggestion == null) {
        continue;
      }
      flushPendingSuggestion();
      suggestions.add(suggestion);
      if (suggestions.length == 3) {
        break;
      }
    }
    flushPendingSuggestion();

    if (suggestions.isEmpty) {
      throw const LocalTerminalAiConfigurationException(
        _unexpectedSuggestionResponseMessage,
      );
    }

    return suggestions;
  }

  LocalTerminalAiSuggestion? _parseSuggestionLine(String rawLine) {
    var line = rawLine.trim();
    if (line.isEmpty ||
        line == '```' ||
        line.startsWith('```') ||
        line.toUpperCase() == 'NO_SUGGESTION') {
      return null;
    }

    line = line.replaceFirst(_suggestionListPrefixPattern, '').trim();
    if (line.isEmpty || line.endsWith(':')) {
      return null;
    }

    var command = line;
    var explanation = 'Suggested by the on-device model.';

    final formattedParts = line.split('||');
    if (formattedParts.length > 1) {
      command = formattedParts.first.trim();
      explanation = formattedParts.sublist(1).join('||').trim();
    } else {
      final commandMatch = _suggestionBacktickPattern.firstMatch(line);
      if (commandMatch case final RegExpMatch commandMatch) {
        command = commandMatch.group(1)!.trim();
        final remainder = line.replaceFirst(commandMatch.group(0)!, '').trim();
        explanation = _normalizeSuggestionExplanation(remainder);
      } else if (_lastSuggestionExplanationSeparator(line) case (
        final int index,
        final int separatorLength,
      )) {
        command = line.substring(0, index).trim();
        explanation = line.substring(index + separatorLength).trim();
      }
    }

    command = _normalizeSuggestionCommand(command);
    explanation = _normalizeSuggestionExplanation(explanation);
    if (command.isEmpty || !_looksLikeShellCommand(command)) {
      return null;
    }

    return LocalTerminalAiSuggestion(
      command: command,
      explanation: explanation,
    );
  }

  LocalTerminalAiSuggestion? _buildSuggestion({
    required String command,
    String? explanation,
  }) {
    final normalizedCommand = _normalizeSuggestionCommand(command);
    final normalizedExplanation = _normalizeSuggestionExplanation(
      explanation ?? 'Suggested by the on-device model.',
    );
    if (normalizedCommand.isEmpty ||
        !_looksLikeShellCommand(normalizedCommand)) {
      return null;
    }
    return LocalTerminalAiSuggestion(
      command: normalizedCommand,
      explanation: normalizedExplanation,
    );
  }

  (String, String?)? _tryParseTaggedSuggestionCommand(String rawLine) {
    final strippedLine = _stripSuggestionLinePrefix(rawLine);
    final command = _stripLeadingLabel(strippedLine, const <String>[
      'CMD:',
      'COMMAND:',
    ]);
    if (command == null) {
      return null;
    }
    final whySeparatorIndex = command.indexOf('||');
    if (whySeparatorIndex == -1) {
      return (command.trim(), null);
    }
    final rawCommand = command.substring(0, whySeparatorIndex).trim();
    final rawExplanation = command.substring(whySeparatorIndex + 2).trim();
    return (
      rawCommand,
      _stripLeadingLabel(rawExplanation, const <String>[
        'WHY:',
        'EXPLANATION:',
      ]),
    );
  }

  String? _tryParseTaggedSuggestionExplanation(String rawLine) =>
      _stripLeadingLabel(_stripSuggestionLinePrefix(rawLine), const <String>[
        'WHY:',
        'EXPLANATION:',
      ]);

  String _stripSuggestionLinePrefix(String rawLine) =>
      rawLine.trim().replaceFirst(_suggestionListPrefixPattern, '').trim();

  String? _stripLeadingLabel(String line, List<String> labels) {
    for (final label in labels) {
      if (line.length >= label.length &&
          line.substring(0, label.length).toUpperCase() == label) {
        return line.substring(label.length).trim();
      }
    }
    return null;
  }

  (int, int)? _lastSuggestionExplanationSeparator(String line) {
    const separators = <String>[' — ', ' – ', ' - '];
    (int, int)? bestMatch;
    for (final separator in separators) {
      final index = line.lastIndexOf(separator);
      if (index <= 0) {
        continue;
      }
      if (bestMatch == null || index > bestMatch.$1) {
        bestMatch = (index, separator.length);
      }
    }
    return bestMatch;
  }

  String _normalizeSuggestionCommand(String command) {
    var normalized = command.trim();
    final taggedCommand = _stripLeadingLabel(normalized, const <String>[
      'CMD:',
      'COMMAND:',
    ]);
    if (taggedCommand != null) {
      normalized = taggedCommand;
    }
    while (normalized.startsWith('`') && normalized.endsWith('`')) {
      normalized = normalized.substring(1, normalized.length - 1).trim();
    }
    normalized = normalized
        .replaceFirst(_suggestionListPrefixPattern, '')
        .trim();
    if ((normalized.startsWith('"') && normalized.endsWith('"')) ||
        (normalized.startsWith("'") && normalized.endsWith("'"))) {
      normalized = normalized.substring(1, normalized.length - 1).trim();
    }
    return normalized;
  }

  String _normalizeSuggestionExplanation(String explanation) {
    final taggedExplanation = _stripLeadingLabel(
      explanation.trim(),
      const <String>['WHY:', 'EXPLANATION:'],
    );
    final normalized = (taggedExplanation ?? explanation)
        .replaceFirst(RegExp(r'^[:\-\u2013\u2014\s]+'), '')
        .trim();
    final collapsedNormalized = normalized.toLowerCase().replaceAll(
      _suggestionWhitespacePattern,
      ' ',
    );
    if (_placeholderSuggestionExplanations.contains(collapsedNormalized)) {
      return 'Suggested by the on-device model.';
    }
    return normalized.isEmpty
        ? 'Suggested by the on-device model.'
        : normalized;
  }

  bool _looksLikeShellCommand(String command) {
    if (command.isEmpty) {
      return false;
    }
    const nonCommandPhrases = <String>{
      'here are some options',
      'here are a few options',
      'here are some suggestions',
      'suggestions',
      'options',
      'commands',
    };
    if (nonCommandPhrases.contains(command.toLowerCase())) {
      return false;
    }
    final normalizedCommand = command.toLowerCase().replaceAll(
      _suggestionWhitespacePattern,
      ' ',
    );
    if (_placeholderSuggestionCommands.contains(normalizedCommand)) {
      return false;
    }
    final firstCodeUnit = command.codeUnitAt(0);
    final startsWithCommandCharacter =
        (firstCodeUnit >= 0x41 && firstCodeUnit <= 0x5A) ||
        (firstCodeUnit >= 0x61 && firstCodeUnit <= 0x7A) ||
        firstCodeUnit == 0x2E ||
        firstCodeUnit == 0x2F ||
        firstCodeUnit == 0x7E;
    if (!startsWithCommandCharacter) {
      return false;
    }
    if (_shellSyntaxCharacterPattern.hasMatch(command)) {
      return true;
    }
    final tokens = command
        .split(RegExp(r'\s+'))
        .where((token) => token.isNotEmpty);
    final tokenList = tokens.toList(growable: false);
    if (tokenList.isEmpty) {
      return false;
    }
    final hasExplicitShellArgument = tokenList
        .skip(1)
        .any(
          (token) =>
              token.startsWith('-') ||
              token.contains('/') ||
              token.contains('.') ||
              token.contains(':') ||
              token.contains('@') ||
              token.contains('=') ||
              token.contains(',') ||
              RegExp(r'\d').hasMatch(token),
        );
    if (hasExplicitShellArgument) {
      return true;
    }
    final allTokensLookShellSafe = tokenList.every(
      _simpleShellTokenPattern.hasMatch,
    );
    if (!allTokensLookShellSafe) {
      return false;
    }
    if (tokenList.length >= 4) {
      return false;
    }
    if (tokenList.length >= 2 &&
        _descriptionLikeLeadingWords.contains(tokenList.first.toLowerCase())) {
      return false;
    }
    return true;
  }

  String _normalizeCompletionSuffix({
    required String currentTerminalLine,
    required String response,
  }) {
    var firstLine = response.replaceAll('\r', '').split('\n').first;
    if (firstLine.trim() == 'NO_COMPLETION') {
      return '';
    }
    const appendPrefix = 'APPEND:';
    if (firstLine.length >= appendPrefix.length &&
        firstLine.substring(0, appendPrefix.length).toUpperCase() ==
            appendPrefix) {
      firstLine = firstLine.substring(appendPrefix.length);
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
    if (_isManagedGemmaPromptTooLongError(error)) {
      return 'Managed ${managedModel.displayName} needs a shorter prompt on this device. Try again with less terminal context.';
    }
    return 'Managed ${managedModel.displayName} failed: $errorMessage';
  }

  bool _isManagedGemmaPromptTooLongError(Object error) {
    final errorMessage = error.toString();
    return errorMessage.contains('Input token ids are too long') ||
        errorMessage.contains('maximum number of tokens allowed');
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
          // ignore: avoid_redundant_argument_values
          maxTokens: managedGemmaMaxTokens,
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
