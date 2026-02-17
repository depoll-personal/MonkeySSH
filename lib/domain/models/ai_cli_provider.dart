/// AI CLI providers supported by the app.
enum AiCliProvider {
  /// Anthropic Claude Code CLI.
  claude,

  /// OpenAI Codex CLI.
  codex,

  /// OpenCode CLI.
  opencode,

  /// GitHub Copilot CLI.
  copilot,

  /// Google Gemini CLI.
  gemini,
}

/// Capability metadata for a provider.
class AiCliProviderCapabilities {
  /// Creates capability metadata.
  const AiCliProviderCapabilities({
    required this.supportsStructuredOutput,
    this.structuredOutputArguments = const <String>[],
    this.composerSlashCommands = const <String>[],
  });

  /// Whether the provider supports structured machine-readable output.
  final bool supportsStructuredOutput;

  /// Arguments used to enable structured output for this provider.
  final List<String> structuredOutputArguments;

  /// Slash commands supported by the provider's interactive composer.
  final List<String> composerSlashCommands;
}

/// Extension that exposes command and capability metadata.
extension AiCliProviderMetadata on AiCliProvider {
  /// Executable name used to launch this provider.
  String get executable => switch (this) {
    AiCliProvider.claude => 'claude',
    AiCliProvider.codex => 'codex',
    AiCliProvider.opencode => 'opencode',
    AiCliProvider.copilot => 'copilot',
    AiCliProvider.gemini => 'gemini',
  };

  /// Metadata describing this provider's capabilities.
  AiCliProviderCapabilities get capabilities => switch (this) {
    AiCliProvider.claude => _claudeCapabilities,
    AiCliProvider.codex => _codexCapabilities,
    AiCliProvider.opencode => _opencodeCapabilities,
    AiCliProvider.copilot => _copilotCapabilities,
    AiCliProvider.gemini => _geminiCapabilities,
  };
}

const _claudeCapabilities = AiCliProviderCapabilities(
  supportsStructuredOutput: true,
  structuredOutputArguments: <String>['--output-format', 'json'],
  composerSlashCommands: <String>['/help', '/clear', '/model', '/compact'],
);
const _codexCapabilities = AiCliProviderCapabilities(
  supportsStructuredOutput: true,
  structuredOutputArguments: <String>['--json'],
  composerSlashCommands: <String>[
    '/help',
    '/clear',
    '/model',
    '/approval-mode',
  ],
);
const _opencodeCapabilities = AiCliProviderCapabilities(
  supportsStructuredOutput: false,
  composerSlashCommands: <String>['/help', '/clear', '/model'],
);
const _copilotCapabilities = AiCliProviderCapabilities(
  supportsStructuredOutput: false,
  composerSlashCommands: <String>['/help', '/clear'],
);
const _geminiCapabilities = AiCliProviderCapabilities(
  supportsStructuredOutput: true,
  structuredOutputArguments: <String>['--format', 'json'],
  composerSlashCommands: <String>['/help', '/clear', '/model'],
);
