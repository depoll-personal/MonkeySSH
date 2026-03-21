import '../models/ai_cli_provider.dart';

/// Persisted steering and session preferences for an AI CLI session.
class AiCliSessionPreferences {
  /// Creates [AiCliSessionPreferences].
  const AiCliSessionPreferences({
    this.providerSessionId,
    this.modelId,
    this.modeId,
    this.systemPrompt,
    this.appendSystemPrompt,
  });

  /// Provider-native session identifier used for resume flows.
  final String? providerSessionId;

  /// Preferred model identifier.
  final String? modelId;

  /// Preferred mode or approval policy identifier.
  final String? modeId;

  /// Provider system prompt replacement.
  final String? systemPrompt;

  /// Provider system prompt extension.
  final String? appendSystemPrompt;

  /// Returns true when any steering field is configured.
  bool get hasSteeringOverrides =>
      _isPresent(modelId) ||
      _isPresent(modeId) ||
      _isPresent(systemPrompt) ||
      _isPresent(appendSystemPrompt);

  /// Returns true when a provider-native session ID is available.
  bool get hasProviderSessionId => _isPresent(providerSessionId);

  /// Returns a copy with updated values.
  AiCliSessionPreferences copyWith({
    String? providerSessionId,
    String? modelId,
    String? modeId,
    String? systemPrompt,
    String? appendSystemPrompt,
  }) => AiCliSessionPreferences(
    providerSessionId: providerSessionId ?? this.providerSessionId,
    modelId: modelId ?? this.modelId,
    modeId: modeId ?? this.modeId,
    systemPrompt: systemPrompt ?? this.systemPrompt,
    appendSystemPrompt: appendSystemPrompt ?? this.appendSystemPrompt,
  );

  /// Serializes the preferences to timeline/session metadata.
  Map<String, dynamic> toMetadata() => <String, dynamic>{
    if (_isPresent(providerSessionId)) 'providerSessionId': providerSessionId,
    if (_isPresent(modelId)) 'currentModelId': modelId,
    if (_isPresent(modeId)) 'currentModeId': modeId,
    if (_isPresent(systemPrompt)) 'systemPrompt': systemPrompt,
    if (_isPresent(appendSystemPrompt))
      'appendSystemPrompt': appendSystemPrompt,
  };

  /// Returns whether [provider] supports launch-time model selection.
  bool supportsModelSelection(AiCliProvider provider) => switch (provider) {
    AiCliProvider.acp => false,
    AiCliProvider.claude ||
    AiCliProvider.codex ||
    AiCliProvider.opencode ||
    AiCliProvider.copilot ||
    AiCliProvider.gemini => true,
  };

  /// Returns whether [provider] supports launch-time mode selection.
  bool supportsModeSelection(AiCliProvider provider) => switch (provider) {
    AiCliProvider.codex || AiCliProvider.gemini => true,
    AiCliProvider.claude ||
    AiCliProvider.opencode ||
    AiCliProvider.copilot ||
    AiCliProvider.acp => false,
  };

  /// Returns whether [provider] supports replacing the system prompt.
  bool supportsSystemPrompt(AiCliProvider provider) => switch (provider) {
    AiCliProvider.claude => true,
    AiCliProvider.codex ||
    AiCliProvider.opencode ||
    AiCliProvider.copilot ||
    AiCliProvider.gemini ||
    AiCliProvider.acp => false,
  };

  /// Returns whether [provider] supports appending to the system prompt.
  bool supportsAppendSystemPrompt(AiCliProvider provider) => switch (provider) {
    AiCliProvider.claude => true,
    AiCliProvider.codex ||
    AiCliProvider.opencode ||
    AiCliProvider.copilot ||
    AiCliProvider.gemini ||
    AiCliProvider.acp => false,
  };

  static bool _isPresent(String? value) => value?.trim().isNotEmpty ?? false;
}
