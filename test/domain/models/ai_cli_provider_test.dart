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

    test('provider auto-start matches launch model', () {
      expect(AiCliProvider.claude.capabilities.autoStartRuntime, isFalse);
      expect(AiCliProvider.codex.capabilities.autoStartRuntime, isFalse);
      expect(AiCliProvider.opencode.capabilities.autoStartRuntime, isFalse);
      expect(AiCliProvider.gemini.capabilities.autoStartRuntime, isTrue);
      expect(AiCliProvider.acp.capabilities.autoStartRuntime, isTrue);
    });

    test('non-copilot providers do not declare ACP support', () {
      expect(AiCliProvider.claude.capabilities.supportsAcp, isFalse);
      expect(AiCliProvider.codex.capabilities.supportsAcp, isFalse);
      expect(AiCliProvider.opencode.capabilities.supportsAcp, isFalse);
      expect(AiCliProvider.gemini.capabilities.supportsAcp, isFalse);
    });

    test('providers expose steering prompt support', () {
      expect(AiCliProvider.claude.capabilities.supportsSteeringPrompts, isTrue);
      expect(AiCliProvider.codex.capabilities.supportsSteeringPrompts, isTrue);
      expect(
        AiCliProvider.opencode.capabilities.supportsSteeringPrompts,
        isTrue,
      );
      expect(
        AiCliProvider.copilot.capabilities.supportsSteeringPrompts,
        isFalse,
      );
      expect(
        AiCliProvider.gemini.capabilities.supportsSteeringPrompts,
        isFalse,
      );
      expect(AiCliProvider.acp.capabilities.supportsSteeringPrompts, isFalse);
    });

    test('interactive adapters requiring TTY are flagged', () {
      expect(AiCliProvider.claude.capabilities.requiresPty, isTrue);
      expect(AiCliProvider.codex.capabilities.requiresPty, isTrue);
      expect(AiCliProvider.opencode.capabilities.requiresPty, isTrue);
      expect(AiCliProvider.copilot.capabilities.requiresPty, isFalse);
    });
  });
}
