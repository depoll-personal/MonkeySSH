// ignore_for_file: public_member_api_docs

import 'package:flutter_test/flutter_test.dart';
import 'package:monkeyssh/domain/models/ai_cli_provider.dart';
import 'package:monkeyssh/domain/services/ai_session_metadata.dart';

void main() {
  group('AiSessionMetadata', () {
    test('reads persisted provider transport metadata', () {
      final metadata = <String, dynamic>{
        'provider': 'codex',
        'transport': 'persistentShell',
      };

      expect(AiSessionMetadata.readProvider(metadata), AiCliProvider.codex);
      expect(
        AiSessionMetadata.readTransport(metadata),
        AiCliTransport.persistentShell,
      );
    });

    test('ignores unknown transport metadata', () {
      final metadata = <String, dynamic>{'transport': 'not-a-transport'};

      expect(AiSessionMetadata.readTransport(metadata), isNull);
    });
  });
}
