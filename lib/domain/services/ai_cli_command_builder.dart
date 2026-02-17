import '../models/ai_cli_provider.dart';

/// Builds shell-safe launch commands for AI CLI providers.
class AiCliCommandBuilder {
  /// Creates a command builder.
  const AiCliCommandBuilder();

  /// Builds a command that launches [provider] from [remoteWorkingDirectory].
  ///
  /// The returned command is intended for remote shell execution over SSH.
  /// Set [structuredOutput] to include provider-specific structured output
  /// arguments when supported.
  String buildLaunchCommand({
    required AiCliProvider provider,
    required String remoteWorkingDirectory,
    bool structuredOutput = false,
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
      if (structuredOutput) ..._structuredOutputArgumentsFor(provider),
      ...extraArguments,
    ];

    final executableCommand = _buildExecutableCommand(
      executable: provider.executable,
      arguments: commandArguments,
    );
    final escapedDirectory = _shellEscape(trimmedRemoteWorkingDirectory);
    return 'cd $escapedDirectory && $executableCommand';
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

  String _buildExecutableCommand({
    required String executable,
    required List<String> arguments,
  }) {
    if (arguments.isEmpty) {
      return executable;
    }
    final escapedArguments = arguments.map(_shellEscape).join(' ');
    return '$executable $escapedArguments';
  }

  String _shellEscape(String value) {
    if (value.isEmpty) {
      return '\'\'';
    }
    final escapedValue = value.replaceAll('\'', '\'\\\'\'');
    return '\'$escapedValue\'';
  }
}
