// ignore_for_file: public_member_api_docs

import 'package:flutter_test/flutter_test.dart';
import 'package:monkeyssh/domain/models/ai_cli_provider.dart';
import 'package:monkeyssh/domain/services/ai_cli_session_preferences.dart';

void main() {
  group('AiCliSessionPreferences', () {
    test('serializes only populated metadata keys', () {
      const preferences = AiCliSessionPreferences(
        providerSessionId: 'session-1',
        modelId: 'sonnet',
        systemPrompt: 'Be concise',
      );

      expect(preferences.toMetadata(), <String, dynamic>{
        'providerSessionId': 'session-1',
        'currentModelId': 'sonnet',
        'systemPrompt': 'Be concise',
      });
    });

    test('reports provider support for launch-time steering fields', () {
      const preferences = AiCliSessionPreferences();

      expect(preferences.supportsModelSelection(AiCliProvider.codex), isTrue);
      expect(preferences.supportsModeSelection(AiCliProvider.gemini), isTrue);
      expect(preferences.supportsSystemPrompt(AiCliProvider.claude), isTrue);
      expect(
        preferences.supportsAppendSystemPrompt(AiCliProvider.claude),
        isTrue,
      );
      expect(preferences.supportsSystemPrompt(AiCliProvider.codex), isFalse);
      expect(preferences.supportsModeSelection(AiCliProvider.copilot), isFalse);
    });
  });
}
