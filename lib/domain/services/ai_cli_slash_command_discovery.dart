import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/ai_cli_provider.dart';
import 'ai_cli_command_builder.dart';

/// Discovers slash commands from provider CLI help output.
class AiCliSlashCommandDiscovery {
  /// Creates an [AiCliSlashCommandDiscovery].
  const AiCliSlashCommandDiscovery({
    AiCliCommandBuilder commandBuilder = const AiCliCommandBuilder(),
  }) : _commandBuilder = commandBuilder;

  final AiCliCommandBuilder _commandBuilder;

  /// Builds a remote command that asks the provider to print its slash-command help.
  String? buildDiscoveryCommand({
    required AiCliProvider provider,
    required String remoteWorkingDirectory,
    String? executableOverride,
  }) {
    final extraArguments = switch (provider) {
      AiCliProvider.claude => const <String>['-p', '/help'],
      AiCliProvider.copilot => const <String>['--prompt', '/help'],
      AiCliProvider.gemini => const <String>['-p', '/help'],
      AiCliProvider.opencode => const <String>['run', '/help'],
      AiCliProvider.codex || AiCliProvider.acp => null,
    };
    if (extraArguments == null) {
      return null;
    }
    return _commandBuilder.buildLaunchCommand(
      provider: provider,
      remoteWorkingDirectory: remoteWorkingDirectory,
      executableOverride: executableOverride,
      extraArguments: extraArguments,
    );
  }

  /// Extracts slash commands from plain-text help output.
  List<String> extractSlashCommands(String output) {
    final matches = RegExp(
      r'(?:(?<=^)|(?<=[\s`(]))/(?:[a-z][a-z0-9-]*)',
      multiLine: true,
      caseSensitive: false,
    ).allMatches(output);
    final commands = <String>{};
    for (final match in matches) {
      final command = match.group(0)?.trim();
      if (command == null || command.isEmpty) {
        continue;
      }
      commands.add(command);
    }
    return commands.toList(growable: false);
  }
}

/// Provider for [AiCliSlashCommandDiscovery].
final aiCliSlashCommandDiscoveryProvider = Provider<AiCliSlashCommandDiscovery>(
  (_) => const AiCliSlashCommandDiscovery(),
);
