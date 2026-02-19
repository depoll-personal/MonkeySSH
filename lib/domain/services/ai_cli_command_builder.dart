import '../models/ai_cli_provider.dart';
import 'shell_escape.dart';

/// Builds shell-safe launch commands for AI CLI providers.
class AiCliCommandBuilder {
  /// Creates a command builder.
  const AiCliCommandBuilder();

  /// Builds a command that launches [provider] from [remoteWorkingDirectory].
  ///
  /// The returned command is intended for remote shell execution over SSH.
  /// Set [structuredOutput] to include provider-specific structured output
  /// arguments when supported. When [acpMode] is true, ACP-specific
  /// arguments are added instead.
  String buildLaunchCommand({
    required AiCliProvider provider,
    required String remoteWorkingDirectory,
    String? executableOverride,
    bool structuredOutput = false,
    bool acpMode = false,
    List<String> extraArguments = const <String>[],
  }) {
    final trimmedRemoteWorkingDirectory = remoteWorkingDirectory.trim();
    if (trimmedRemoteWorkingDirectory.isEmpty) {
      throw ArgumentError.value(
        remoteWorkingDirectory,
        'remoteWorkingDirectory',
        'Remote working directory cannot be empty.',
      );
    }

    final commandArguments = <String>[
      if (acpMode) ...provider.capabilities.acpLaunchArguments,
      if (structuredOutput && !acpMode)
        ..._structuredOutputArgumentsFor(provider),
      ...extraArguments,
    ];

    final executableCommand = _buildLaunchExecutableCommand(
      provider: provider,
      executableOverride: executableOverride,
      arguments: commandArguments,
    );
    final cdDirectory = _buildCdDirectory(trimmedRemoteWorkingDirectory);
    final bootstrapSegments = <String>[
      r'PATH="$PATH:$HOME/.local/bin:$HOME/bin:/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin"',
      'export PATH',
      r'if [ -f "$HOME/.profile" ]; then . "$HOME/.profile" >/dev/null 2>&1; fi',
      r'if [ -f "$HOME/.bashrc" ]; then . "$HOME/.bashrc" >/dev/null 2>&1; fi',
      r'if [ -f "$HOME/.zprofile" ]; then . "$HOME/.zprofile" >/dev/null 2>&1; fi',
      'cd $cdDirectory && exec $executableCommand',
    ];
    // Use POSIX `sh -c` instead of hard-requiring bash so this works on hosts
    // where bash is unavailable.
    return 'sh -c ${shellEscape(bootstrapSegments.join('; '))}';
  }

  /// Builds a shell-safe cd target that preserves tilde expansion.
  String _buildCdDirectory(String directory) {
    if (directory == '~') {
      return '~';
    }
    if (directory.startsWith('~/')) {
      final rest = directory.substring(2);
      return rest.isEmpty ? '~' : '~/${shellEscape(rest)}';
    }
    return shellEscape(directory);
  }

  List<String> _structuredOutputArgumentsFor(AiCliProvider provider) {
    final capabilities = provider.capabilities;
    if (!capabilities.supportsStructuredOutput) {
      throw UnsupportedError(
        '${provider.executable} does not support structured output.',
      );
    }
    return capabilities.structuredOutputArguments;
  }

  String _buildLaunchExecutableCommand({
    required AiCliProvider provider,
    required String? executableOverride,
    required List<String> arguments,
  }) {
    final executable = (executableOverride ?? provider.executable).trim();
    if (executable.isEmpty) {
      throw ArgumentError.value(
        executableOverride,
        'executableOverride',
        'Executable override cannot be empty.',
      );
    }
    if (arguments.isEmpty) {
      return executable;
    }
    final escapedArguments = arguments.map(shellEscape).join(' ');
    return '$executable $escapedArguments';
  }
}
