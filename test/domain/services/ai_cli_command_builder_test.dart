// ignore_for_file: public_member_api_docs

import 'package:flutter_test/flutter_test.dart';
import 'package:monkeyssh/domain/models/ai_cli_provider.dart';
import 'package:monkeyssh/domain/services/ai_cli_command_builder.dart';

void main() {
  group('AiCliCommandBuilder', () {
    const builder = AiCliCommandBuilder();

    test('builds base launch command for each provider', () {
      const remoteWorkingDirectory = '/srv/project';
      const expectedExecutables = <AiCliProvider, String>{
        AiCliProvider.claude: 'claude',
        AiCliProvider.codex: 'codex',
        AiCliProvider.opencode: 'opencode',
        AiCliProvider.copilot: 'copilot',
        AiCliProvider.gemini: 'gemini',
        AiCliProvider.acp: 'acp-client',
      };

      for (final entry in expectedExecutables.entries) {
        final command = builder.buildLaunchCommand(
          provider: entry.key,
          remoteWorkingDirectory: remoteWorkingDirectory,
        );
        expect(command, 'cd \'/srv/project\' && ${entry.value}');
      }
    });

    test('adds provider structured output arguments when requested', () {
      final command = builder.buildLaunchCommand(
        provider: AiCliProvider.claude,
        remoteWorkingDirectory: '/srv/project',
        structuredOutput: true,
      );

      expect(
        command,
        'cd \'/srv/project\' && claude \'--output-format\' \'json\'',
      );
    });

    test('throws for structured output when provider does not support it', () {
      expect(
        () => builder.buildLaunchCommand(
          provider: AiCliProvider.copilot,
          remoteWorkingDirectory: '/srv/project',
          structuredOutput: true,
        ),
        throwsUnsupportedError,
      );
    });

    test('shell-escapes directory and arguments', () {
      final command = builder.buildLaunchCommand(
        provider: AiCliProvider.codex,
        remoteWorkingDirectory: '/srv/it\'s-here',
        extraArguments: const <String>['--message', 'ship it'],
      );

      expect(
        command,
        'cd \'/srv/it\'\\\'\'s-here\' && codex \'--message\' \'ship it\'',
      );
    });

    test('uses executable override for ACP-compatible clients', () {
      final command = builder.buildLaunchCommand(
        provider: AiCliProvider.acp,
        executableOverride: 'my-acp-client --stdio',
        remoteWorkingDirectory: '/srv/project',
        extraArguments: const <String>['--workspace', '.'],
      );

      expect(
        command,
        'cd \'/srv/project\' && my-acp-client --stdio \'--workspace\' \'.\'',
      );
    });

    test('throws when remote working directory is empty', () {
      expect(
        () => builder.buildLaunchCommand(
          provider: AiCliProvider.gemini,
          remoteWorkingDirectory: '   ',
        ),
        throwsArgumentError,
      );
    });
  });
}
