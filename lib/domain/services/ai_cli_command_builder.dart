import 'dart:convert';

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

    final runSegment = _buildRunSegment(
      provider: provider,
      executableOverride: executableOverride,
      arguments: commandArguments,
    );
    final cdDirectory = _buildCdDirectory(trimmedRemoteWorkingDirectory);
    // Suppress PTY echo for adapter-mode processes so the user's stdin input
    // isn't echoed back on stdout as spurious assistant messages.
    final echoSuppression = !acpMode && provider.capabilities.requiresPty
        ? 'stty -echo 2>/dev/null; '
        : '';
    final providerEnvBootstrap = provider == AiCliProvider.gemini
        ? r'if [ -z "${SSL_CERT_FILE:-}" ] && command -v brew >/dev/null 2>&1; then MONKEYSSH_SSL_CERT_FILE="$(brew --prefix)/etc/ca-certificates/certDD.pem"; if [ -f "$MONKEYSSH_SSL_CERT_FILE" ]; then export SSL_CERT_FILE="$MONKEYSSH_SSL_CERT_FILE"; fi; fi; '
        : '';
    final runCommand =
        '$echoSuppression$providerEnvBootstrap'
        'cd $cdDirectory && $runSegment';
    final encodedRunCommand = base64Encode(utf8.encode(runCommand));
    final encodedRunCommandAssignment =
        'MONKEYSSH_RUN_B64=${shellEscape(encodedRunCommand)}';
    const decodeRunCommand =
        r'MONKEYSSH_RUN="$(printf %s "$MONKEYSSH_RUN_B64" | base64 --decode 2>/dev/null || printf %s "$MONKEYSSH_RUN_B64" | base64 -d 2>/dev/null)"';
    const loginShellCommand =
        r'if [ -n "$SHELL" ] && command -v "$SHELL" >/dev/null 2>&1; then "$SHELL" -ilc "$MONKEYSSH_RUN"; rc=$?; if [ $rc -ne 127 ]; then exit $rc; fi; fi';
    final loginShellSegments = <String>[
      encodedRunCommandAssignment,
      decodeRunCommand,
      'export MONKEYSSH_RUN',
      loginShellCommand,
      r'if command -v zsh >/dev/null 2>&1; then zsh -ilc "$MONKEYSSH_RUN"; rc=$?; if [ $rc -ne 127 ]; then exit $rc; fi; fi',
      r'if command -v bash >/dev/null 2>&1; then bash -ilc "$MONKEYSSH_RUN"; rc=$?; if [ $rc -ne 127 ]; then exit $rc; fi; fi',
    ];
    final fallbackSegments = <String>[
      r'PATH="$PATH:$HOME/.local/bin:$HOME/bin:$HOME/homebrew/bin:$HOME/.homebrew/bin:/usr/local/bin:/usr/local/sbin:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/bin:/bin:/usr/sbin:/sbin"',
      'export PATH',
      r'if [ -f "$HOME/.profile" ]; then . "$HOME/.profile" >/dev/null 2>&1; fi',
      r'if [ -f "$HOME/.bash_profile" ]; then . "$HOME/.bash_profile" >/dev/null 2>&1; fi',
      r'if [ -f "$HOME/.bashrc" ]; then . "$HOME/.bashrc" >/dev/null 2>&1; fi',
      r'if [ -f "$HOME/.zprofile" ]; then . "$HOME/.zprofile" >/dev/null 2>&1; fi',
      r'if [ -f "$HOME/.zshrc" ]; then . "$HOME/.zshrc" >/dev/null 2>&1; fi',
      runCommand,
    ];
    final launchSegments = <String>[...loginShellSegments, ...fallbackSegments];
    // Use POSIX `sh -c` instead of hard-requiring bash so this works on hosts
    // where bash is unavailable.
    return 'sh -c ${shellEscape(launchSegments.join('; '))}';
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

  String _resolveExecutableLookupToken({
    required AiCliProvider provider,
    required String? executableOverride,
  }) {
    final executable = (executableOverride ?? provider.executable).trim();
    if (executable.isEmpty) {
      return provider.executable;
    }
    final firstSpace = executable.indexOf(' ');
    if (firstSpace == -1) {
      return executable;
    }
    return executable.substring(0, firstSpace).trim();
  }

  String _buildRunSegment({
    required AiCliProvider provider,
    required String? executableOverride,
    required List<String> arguments,
  }) {
    final hasOverride =
        executableOverride != null && executableOverride.trim().isNotEmpty;
    if (provider == AiCliProvider.claude && !hasOverride) {
      final escapedArguments = arguments.map(shellEscape).join(' ');
      final argumentSuffix = escapedArguments.isEmpty
          ? ''
          : ' $escapedArguments';
      return 'if command -v claude >/dev/null 2>&1; then exec claude$argumentSuffix; fi; '
          'if command -v claude-code >/dev/null 2>&1; then exec claude-code$argumentSuffix; fi; '
          'if command -v npx >/dev/null 2>&1; then exec npx --yes @anthropic-ai/claude-code$argumentSuffix; fi; '
          'echo "monkeyssh: executable not found: \'claude\' (PATH=\$PATH)" >&2; '
          'exit 127';
    }
    final executableCommand = _buildLaunchExecutableCommand(
      provider: provider,
      executableOverride: executableOverride,
      arguments: arguments,
    );
    final executableLookup = _resolveExecutableLookupToken(
      provider: provider,
      executableOverride: executableOverride,
    );
    return 'if ! command -v ${shellEscape(executableLookup)} >/dev/null 2>&1; then '
        'echo "monkeyssh: executable not found: ${shellEscape(executableLookup)} (PATH=\$PATH)" >&2; '
        'exit 127; fi; '
        'exec $executableCommand';
  }
}
