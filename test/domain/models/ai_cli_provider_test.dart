// ignore_for_file: public_member_api_docs

import 'package:flutter_test/flutter_test.dart';
import 'package:monkeyssh/domain/models/ai_cli_provider.dart';

void main() {
  group('AiCliProvider capabilities', () {
    test('copilot disables auto-start runtime', () {
      expect(AiCliProvider.copilot.capabilities.autoStartRuntime, isFalse);
    });

    test('other built-in providers keep runtime auto-start enabled', () {
      expect(AiCliProvider.claude.capabilities.autoStartRuntime, isTrue);
      expect(AiCliProvider.codex.capabilities.autoStartRuntime, isTrue);
      expect(AiCliProvider.opencode.capabilities.autoStartRuntime, isTrue);
      expect(AiCliProvider.gemini.capabilities.autoStartRuntime, isTrue);
      expect(AiCliProvider.acp.capabilities.autoStartRuntime, isTrue);
    });
  });
}
