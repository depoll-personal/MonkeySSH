import '../models/ai_cli_provider.dart';
import 'ai_cli_session_preferences.dart';

/// Builds provider-specific launch arguments for interactive and prompt modes.
class AiCliLaunchArgumentsBuilder {
  /// Creates an [AiCliLaunchArgumentsBuilder].
  const AiCliLaunchArgumentsBuilder();

  /// Returns launch arguments for a persistent interactive session.
  List<String> buildPersistentLaunchArguments({
    required AiCliProvider provider,
    required AiCliSessionPreferences preferences,
    required bool resumedSession,
  }) => switch (provider) {
    AiCliProvider.claude => _claudePersistentArguments(
      preferences: preferences,
      resumedSession: resumedSession,
    ),
    AiCliProvider.codex => _codexPersistentArguments(
      preferences: preferences,
      resumedSession: resumedSession,
    ),
    AiCliProvider.opencode ||
    AiCliProvider.copilot ||
    AiCliProvider.gemini ||
    AiCliProvider.acp => const <String>[],
  };

  /// Returns launch arguments for a single prompt turn.
  List<String> buildHeadlessPromptArguments({
    required AiCliProvider provider,
    required AiCliSessionPreferences preferences,
    required String prompt,
  }) => switch (provider) {
    AiCliProvider.claude => <String>[
      '-p',
      '--verbose',
      '--output-format',
      'stream-json',
      ...?_claudeResumeArguments(preferences),
      ...?_modelArguments(flag: '--model', modelId: preferences.modelId),
      ...?_singleValueArguments(
        flag: '--system-prompt',
        value: preferences.systemPrompt,
      ),
      ...?_singleValueArguments(
        flag: '--append-system-prompt',
        value: preferences.appendSystemPrompt,
      ),
      prompt,
    ],
    AiCliProvider.codex => <String>[
      'exec',
      ...?_codexExecResumeArguments(preferences),
      '--json',
      ...?_modelArguments(flag: '--model', modelId: preferences.modelId),
      ...?_singleValueArguments(
        flag: '--ask-for-approval',
        value: preferences.modeId,
      ),
      prompt,
    ],
    AiCliProvider.opencode => <String>[
      'run',
      '--format',
      'json',
      ...?_singleValueArguments(
        flag: '--session',
        value: preferences.providerSessionId,
      ),
      ...?_modelArguments(flag: '--model', modelId: preferences.modelId),
      prompt,
    ],
    AiCliProvider.copilot => <String>[
      if (_isPresent(preferences.providerSessionId))
        '--resume=${preferences.providerSessionId!.trim()}',
      '--prompt',
      prompt,
      '--output-format',
      'json',
      '--allow-all-tools',
      ...?_modelArguments(flag: '--model', modelId: preferences.modelId),
    ],
    AiCliProvider.gemini => <String>[
      ...?_singleValueArguments(
        flag: '--resume',
        value: preferences.providerSessionId,
      ),
      '-p',
      prompt,
      '--output-format',
      'stream-json',
      ...?_modelArguments(flag: '--model', modelId: preferences.modelId),
      ...?_singleValueArguments(
        flag: '--approval-mode',
        value: preferences.modeId,
      ),
    ],
    AiCliProvider.acp => throw UnsupportedError(
      'Headless prompt mode is not supported for ACP custom clients.',
    ),
  };

  List<String> _claudePersistentArguments({
    required AiCliSessionPreferences preferences,
    required bool resumedSession,
  }) => <String>[
    ...?(resumedSession ? _claudeResumeArguments(preferences) : null),
    ...?_modelArguments(flag: '--model', modelId: preferences.modelId),
    ...?_singleValueArguments(
      flag: '--system-prompt',
      value: preferences.systemPrompt,
    ),
    ...?_singleValueArguments(
      flag: '--append-system-prompt',
      value: preferences.appendSystemPrompt,
    ),
  ];

  List<String> _codexPersistentArguments({
    required AiCliSessionPreferences preferences,
    required bool resumedSession,
  }) => <String>[
    if (resumedSession && _isPresent(preferences.providerSessionId))
      'resume'
    else
      ...const <String>[],
    if (resumedSession && _isPresent(preferences.providerSessionId))
      preferences.providerSessionId!.trim(),
    '--no-alt-screen',
    ...?_modelArguments(flag: '--model', modelId: preferences.modelId),
    ...?_singleValueArguments(
      flag: '--ask-for-approval',
      value: preferences.modeId,
    ),
  ];

  List<String>? _claudeResumeArguments(AiCliSessionPreferences preferences) =>
      _singleValueArguments(
        flag: '--resume',
        value: preferences.providerSessionId,
      );

  List<String>? _codexExecResumeArguments(AiCliSessionPreferences preferences) {
    if (!_isPresent(preferences.providerSessionId)) {
      return null;
    }
    return <String>['resume', preferences.providerSessionId!.trim()];
  }

  List<String>? _modelArguments({
    required String flag,
    required String? modelId,
  }) => _singleValueArguments(flag: flag, value: modelId);

  List<String>? _singleValueArguments({
    required String flag,
    required String? value,
  }) {
    if (!_isPresent(value)) {
      return null;
    }
    return <String>[flag, value!.trim()];
  }

  static bool _isPresent(String? value) => value?.trim().isNotEmpty ?? false;
}
