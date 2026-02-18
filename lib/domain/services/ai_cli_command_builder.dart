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
    final innerCommand = 'cd $cdDirectory && exec $executableCommand';
    // Wrap in a login shell so the user's PATH (from .profile / .bashrc)
    // is available — SSH exec channels are non-interactive by default.
    return 'bash -lc ${shellEscape(innerCommand)}';
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
