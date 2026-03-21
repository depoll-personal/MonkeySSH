// ignore_for_file: public_member_api_docs

import 'package:flutter_test/flutter_test.dart';
import 'package:monkeyssh/domain/models/ai_cli_provider.dart';
import 'package:monkeyssh/domain/services/ai_cli_slash_command_discovery.dart';

void main() {
  group('AiCliSlashCommandDiscovery', () {
    const discovery = AiCliSlashCommandDiscovery();

    test('builds discovery commands for supported providers', () {
      final command = discovery.buildDiscoveryCommand(
        provider: AiCliProvider.gemini,
        remoteWorkingDirectory: '/repo',
      );

      expect(command, isNotNull);
      expect(command, contains('/help'));
    });

    test('skips discovery for unsupported providers', () {
      final command = discovery.buildDiscoveryCommand(
        provider: AiCliProvider.codex,
        remoteWorkingDirectory: '/repo',
      );

      expect(command, isNull);
    });

    test('extracts slash commands from help output', () {
      final commands = discovery.extractSlashCommands('''
### /help
Use /model set to switch models.
Run /resume save checkpoint to keep your place.
`/tools`
See https://example.com/docs/reference for docs.
''');

      expect(
        commands,
        equals(<String>['/help', '/model', '/resume', '/tools']),
      );
    });
  });
}
