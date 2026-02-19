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
        expect(command, startsWith('sh -c '));
        expect(command, contains('/srv/project'));
        expect(command, contains('&&'));
        expect(command, contains('exec'));
        expect(command, contains(entry.value));
      }
    });

    test('adds provider structured output arguments when requested', () {
      final command = builder.buildLaunchCommand(
        provider: AiCliProvider.claude,
        remoteWorkingDirectory: '/srv/project',
        structuredOutput: true,
      );

      expect(command, startsWith('sh -c '));
      expect(command, contains('claude'));
      expect(command, contains('--output-format'));
      expect(command, contains('json'));
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

    test('preserves tilde expansion in working directory', () {
      final command = builder.buildLaunchCommand(
        provider: AiCliProvider.claude,
        remoteWorkingDirectory: '~',
      );

      expect(command, startsWith('sh -c '));
      expect(command, contains('cd ~ && if command -v claude'));
      expect(command, contains('exec claude'));

      final commandSubdir = builder.buildLaunchCommand(
        provider: AiCliProvider.claude,
        remoteWorkingDirectory: '~/projects/my-app',
      );

      expect(commandSubdir, startsWith('sh -c '));
      expect(commandSubdir, contains('cd ~/'));
      expect(commandSubdir, contains('projects/my-app'));
      expect(commandSubdir, contains('claude'));
    });

    test('adds Claude executable fallbacks when override is not set', () {
      final command = builder.buildLaunchCommand(
        provider: AiCliProvider.claude,
        remoteWorkingDirectory: '/srv/project',
      );

      expect(command, contains('command -v claude-code'));
      expect(command, contains('npx --yes @anthropic-ai/claude-code'));
    });

    test('uses executable override for ACP-compatible clients', () {
      final command = builder.buildLaunchCommand(
        provider: AiCliProvider.acp,
        executableOverride: 'my-acp-client --stdio',
        remoteWorkingDirectory: '/srv/project',
        extraArguments: const <String>['--workspace', '.'],
      );

      expect(command, startsWith('sh -c '));
      expect(command, contains('my-acp-client --stdio'));
      expect(command, contains('--workspace'));
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

    test('adds ACP launch arguments when acpMode is true', () {
      final command = builder.buildLaunchCommand(
        provider: AiCliProvider.copilot,
        remoteWorkingDirectory: '/srv/project',
        acpMode: true,
      );

      expect(command, startsWith('sh -c '));
      expect(command, contains('copilot'));
      expect(command, contains('--acp'));
      expect(command, contains('--allow-all-tools'));
    });

    test('acpMode suppresses structured output arguments', () {
      final command = builder.buildLaunchCommand(
        provider: AiCliProvider.copilot,
        remoteWorkingDirectory: '/srv/project',
        acpMode: true,
        structuredOutput: true,
      );

      expect(command, startsWith('sh -c '));
      expect(command, contains('--acp'));
      expect(command, isNot(contains('--output-format')));
    });
  });
}
