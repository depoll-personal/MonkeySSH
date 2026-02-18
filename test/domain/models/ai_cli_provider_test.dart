// ignore_for_file: public_member_api_docs

import 'package:flutter_test/flutter_test.dart';
import 'package:monkeyssh/domain/models/ai_cli_provider.dart';

void main() {
  group('AiCliProvider capabilities', () {
    test('copilot supports ACP and auto-starts runtime', () {
      expect(AiCliProvider.copilot.capabilities.supportsAcp, isTrue);
      expect(AiCliProvider.copilot.capabilities.autoStartRuntime, isTrue);
      expect(
        AiCliProvider.copilot.capabilities.acpLaunchArguments,
        contains('--acp'),
      );
    });

    test('other built-in providers keep runtime auto-start enabled', () {
      expect(AiCliProvider.claude.capabilities.autoStartRuntime, isTrue);
      expect(AiCliProvider.codex.capabilities.autoStartRuntime, isTrue);
      expect(AiCliProvider.opencode.capabilities.autoStartRuntime, isTrue);
      expect(AiCliProvider.gemini.capabilities.autoStartRuntime, isTrue);
      expect(AiCliProvider.acp.capabilities.autoStartRuntime, isTrue);
    });

    test('non-copilot providers do not declare ACP support', () {
      expect(AiCliProvider.claude.capabilities.supportsAcp, isFalse);
      expect(AiCliProvider.codex.capabilities.supportsAcp, isFalse);
      expect(AiCliProvider.opencode.capabilities.supportsAcp, isFalse);
      expect(AiCliProvider.gemini.capabilities.supportsAcp, isFalse);
    });
  });
}
