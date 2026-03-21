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

/// Transport modes supported by provider integrations.
enum AiCliTransport {
  /// ACP protocol session over stdio.
  acp('ACP'),

  /// Long-lived interactive shell session over SSH.
  persistentShell('Interactive'),

  /// Per-turn prompt execution with structured output.
  headlessPrompt('Prompt');

  /// Creates an [AiCliTransport].
  const AiCliTransport(this.label);

  /// Human-friendly transport label for UI.
  final String label;
}

/// Capability metadata for a provider.
class AiCliProviderCapabilities {
  /// Creates capability metadata.
  const AiCliProviderCapabilities({
    required this.supportedTransports,
    required this.supportsStructuredOutput,
    this.structuredOutputArguments = const <String>[],
    this.composerSlashCommands = const <String>[],
    this.supportsSteeringPrompts = false,
    this.requiresPty = false,
    this.autoStartRuntime = true,
    this.acpLaunchArguments = const <String>[],
  });

  /// Ordered transports supported by this provider.
  ///
  /// The first transport is treated as the default launch mode and later
  /// entries are graceful fallbacks when the preferred mode is unavailable.
  final List<AiCliTransport> supportedTransports;

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
  bool get supportsAcp => supportedTransports.contains(AiCliTransport.acp);

  /// CLI arguments used to launch this provider in ACP mode.
  final List<String> acpLaunchArguments;

  /// Whether the provider supports one-shot prompt execution with
  /// machine-readable output and resumable session identifiers.
  bool get supportsHeadlessPromptMode =>
      supportedTransports.contains(AiCliTransport.headlessPrompt);

  /// Default transport used when no session preference is persisted.
  AiCliTransport get defaultTransport => supportedTransports.first;

  /// Returns whether [transport] is supported by this provider.
  bool supportsTransport(AiCliTransport transport) =>
      supportedTransports.contains(transport);

  /// Returns the next fallback transport after [transport], if any.
  AiCliTransport? fallbackTransportFor(AiCliTransport transport) {
    final currentIndex = supportedTransports.indexOf(transport);
    if (currentIndex == -1) {
      return null;
    }
    final nextIndex = currentIndex + 1;
    if (nextIndex >= supportedTransports.length) {
      return null;
    }
    return supportedTransports[nextIndex];
  }
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
  supportedTransports: <AiCliTransport>[
    AiCliTransport.persistentShell,
    AiCliTransport.headlessPrompt,
  ],
  supportsStructuredOutput: true,
  structuredOutputArguments: <String>['--output-format', 'stream-json'],
  composerSlashCommands: <String>['/help', '/model'],
  supportsSteeringPrompts: true,
  requiresPty: true,
  autoStartRuntime: false,
);
const _codexCapabilities = AiCliProviderCapabilities(
  supportedTransports: <AiCliTransport>[
    AiCliTransport.persistentShell,
    AiCliTransport.headlessPrompt,
  ],
  supportsStructuredOutput: true,
  structuredOutputArguments: <String>['exec', '--json'],
  supportsSteeringPrompts: true,
  requiresPty: true,
  autoStartRuntime: false,
);
const _opencodeCapabilities = AiCliProviderCapabilities(
  supportedTransports: <AiCliTransport>[
    AiCliTransport.acp,
    AiCliTransport.headlessPrompt,
  ],
  supportsStructuredOutput: true,
  structuredOutputArguments: <String>['run', '--format', 'json'],
  composerSlashCommands: <String>['/help', '/model'],
  supportsSteeringPrompts: true,
  acpLaunchArguments: <String>['acp'],
);
const _copilotCapabilities = AiCliProviderCapabilities(
  supportedTransports: <AiCliTransport>[
    AiCliTransport.acp,
    AiCliTransport.headlessPrompt,
  ],
  supportsStructuredOutput: true,
  structuredOutputArguments: <String>['--output-format', 'json'],
  composerSlashCommands: <String>['/help', '/model'],
  acpLaunchArguments: <String>['--acp', '--allow-all-tools'],
);
const _geminiCapabilities = AiCliProviderCapabilities(
  supportedTransports: <AiCliTransport>[
    AiCliTransport.acp,
    AiCliTransport.headlessPrompt,
  ],
  supportsStructuredOutput: true,
  structuredOutputArguments: <String>['--output-format', 'stream-json'],
  composerSlashCommands: <String>['/help', '/model'],
  acpLaunchArguments: <String>['--acp'],
);
const _acpCapabilities = AiCliProviderCapabilities(
  supportedTransports: <AiCliTransport>[AiCliTransport.acp],
  supportsStructuredOutput: false,
  composerSlashCommands: <String>['/help'],
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
  AcpClientPreset(id: 'opencode', label: 'OpenCode', command: 'opencode acp'),
  AcpClientPreset(
    id: 'copilot',
    label: 'GitHub Copilot',
    command: 'copilot --acp --allow-all-tools',
  ),
  AcpClientPreset(id: 'gemini', label: 'Gemini CLI', command: 'gemini --acp'),
  AcpClientPreset(
    id: 'claude-acp',
    label: 'Claude Code via ACP Adapter',
    command: 'acp-adapter --adapter claude',
  ),
  AcpClientPreset(
    id: 'codex-acp',
    label: 'Codex via ACP Adapter',
    command: 'acp-adapter --adapter codex',
  ),
  AcpClientPreset(
    id: 'generic-stdio',
    label: 'Generic ACP Client (stdio)',
    command: 'acp-client --stdio',
  ),
];
