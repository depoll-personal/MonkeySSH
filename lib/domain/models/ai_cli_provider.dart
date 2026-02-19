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

  /// Generic ACP-compatible client command.
  acp,
}

/// Capability metadata for a provider.
class AiCliProviderCapabilities {
  /// Creates capability metadata.
  const AiCliProviderCapabilities({
    required this.supportsStructuredOutput,
    this.structuredOutputArguments = const <String>[],
    this.composerSlashCommands = const <String>[],
    this.supportsSteeringPrompts = false,
    this.requiresPty = false,
    this.autoStartRuntime = true,
    this.supportsAcp = false,
    this.acpLaunchArguments = const <String>[],
  });

  /// Whether the provider supports structured machine-readable output.
  final bool supportsStructuredOutput;

  /// Arguments used to enable structured output for this provider.
  final List<String> structuredOutputArguments;

  /// Slash commands supported by the provider's interactive composer.
  final List<String> composerSlashCommands;

  /// Whether the provider supports queued steering prompts.
  final bool supportsSteeringPrompts;

  /// Whether the runtime must allocate a PTY when launching this provider.
  final bool requiresPty;

  /// Whether sessions for this provider should auto-start on screen open.
  final bool autoStartRuntime;

  /// Whether the provider supports the Agent Client Protocol (ACP).
  final bool supportsAcp;

  /// CLI arguments used to launch this provider in ACP mode.
  final List<String> acpLaunchArguments;
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
    AiCliProvider.acp => 'acp-client',
  };

  /// Metadata describing this provider's capabilities.
  AiCliProviderCapabilities get capabilities => switch (this) {
    AiCliProvider.claude => _claudeCapabilities,
    AiCliProvider.codex => _codexCapabilities,
    AiCliProvider.opencode => _opencodeCapabilities,
    AiCliProvider.copilot => _copilotCapabilities,
    AiCliProvider.gemini => _geminiCapabilities,
    AiCliProvider.acp => _acpCapabilities,
  };
}

const _claudeCapabilities = AiCliProviderCapabilities(
  supportsStructuredOutput: true,
  structuredOutputArguments: <String>['--output-format', 'json'],
  composerSlashCommands: <String>['/help', '/clear', '/model', '/compact'],
  supportsSteeringPrompts: true,
  autoStartRuntime: false,
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
  supportsSteeringPrompts: true,
  autoStartRuntime: false,
);
const _opencodeCapabilities = AiCliProviderCapabilities(
  supportsStructuredOutput: false,
  composerSlashCommands: <String>['/help', '/clear', '/model'],
  supportsSteeringPrompts: true,
  autoStartRuntime: false,
);
const _copilotCapabilities = AiCliProviderCapabilities(
  supportsStructuredOutput: false,
  composerSlashCommands: <String>['/help', '/clear'],
  supportsAcp: true,
  acpLaunchArguments: <String>['--acp', '--allow-all-tools'],
);
const _geminiCapabilities = AiCliProviderCapabilities(
  supportsStructuredOutput: false,
  composerSlashCommands: <String>['/help', '/clear', '/model'],
);
const _acpCapabilities = AiCliProviderCapabilities(
  supportsStructuredOutput: false,
  composerSlashCommands: <String>['/help', '/clear'],
  supportsAcp: true,
);

/// Preset configuration for a known ACP-compatible client launch command.
class AcpClientPreset {
  /// Creates an [AcpClientPreset].
  const AcpClientPreset({
    required this.id,
    required this.label,
    required this.command,
  });

  /// Stable identifier persisted in session metadata.
  final String id;

  /// Human-friendly name shown in selection UI.
  final String label;

  /// Remote shell command used to launch this client.
  final String command;
}

/// Built-in ACP-compatible client presets shown in the start flow.
const knownAcpClientPresets = <AcpClientPreset>[
  AcpClientPreset(id: 'claude', label: 'Claude Code', command: 'claude'),
  AcpClientPreset(id: 'codex', label: 'Codex', command: 'codex'),
  AcpClientPreset(id: 'opencode', label: 'OpenCode', command: 'opencode'),
  AcpClientPreset(id: 'copilot', label: 'GitHub Copilot', command: 'copilot'),
  AcpClientPreset(id: 'gemini', label: 'Gemini CLI', command: 'gemini'),
  AcpClientPreset(
    id: 'generic-stdio',
    label: 'Generic ACP Client (stdio)',
    command: 'acp-client --stdio',
  ),
];
