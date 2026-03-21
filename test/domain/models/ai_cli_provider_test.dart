// ignore_for_file: public_member_api_docs

import 'package:flutter_test/flutter_test.dart';
import 'package:monkeyssh/domain/models/ai_cli_provider.dart';

void main() {
  group('AiCliProvider capabilities', () {
    test('provider auto-start matches transport model', () {
      expect(AiCliProvider.claude.capabilities.autoStartRuntime, isFalse);
      expect(AiCliProvider.codex.capabilities.autoStartRuntime, isFalse);
      expect(AiCliProvider.opencode.capabilities.autoStartRuntime, isTrue);
      expect(AiCliProvider.copilot.capabilities.autoStartRuntime, isTrue);
      expect(AiCliProvider.gemini.capabilities.autoStartRuntime, isTrue);
      expect(AiCliProvider.acp.capabilities.autoStartRuntime, isTrue);
    });

    test('providers declare ACP support only where the CLI exposes it', () {
      expect(AiCliProvider.claude.capabilities.supportsAcp, isFalse);
      expect(AiCliProvider.codex.capabilities.supportsAcp, isFalse);
      expect(AiCliProvider.opencode.capabilities.supportsAcp, isTrue);
      expect(AiCliProvider.copilot.capabilities.supportsAcp, isTrue);
      expect(AiCliProvider.gemini.capabilities.supportsAcp, isTrue);
    });

    test('providers expose headless prompt mode where supported', () {
      expect(
        AiCliProvider.claude.capabilities.supportsHeadlessPromptMode,
        isTrue,
      );
      expect(
        AiCliProvider.codex.capabilities.supportsHeadlessPromptMode,
        isTrue,
      );
      expect(
        AiCliProvider.opencode.capabilities.supportsHeadlessPromptMode,
        isTrue,
      );
      expect(
        AiCliProvider.copilot.capabilities.supportsHeadlessPromptMode,
        isTrue,
      );
      expect(
        AiCliProvider.gemini.capabilities.supportsHeadlessPromptMode,
        isTrue,
      );
      expect(
        AiCliProvider.acp.capabilities.supportsHeadlessPromptMode,
        isFalse,
      );
    });

    test('providers declare transport order explicitly', () {
      expect(
        AiCliProvider.claude.capabilities.supportedTransports,
        equals(const <AiCliTransport>[
          AiCliTransport.persistentShell,
          AiCliTransport.headlessPrompt,
        ]),
      );
      expect(
        AiCliProvider.codex.capabilities.defaultTransport,
        AiCliTransport.persistentShell,
      );
      expect(
        AiCliProvider.opencode.capabilities.supportedTransports,
        equals(const <AiCliTransport>[
          AiCliTransport.acp,
          AiCliTransport.headlessPrompt,
        ]),
      );
      expect(
        AiCliProvider.copilot.capabilities.defaultTransport,
        AiCliTransport.acp,
      );
      expect(
        AiCliProvider.gemini.capabilities.fallbackTransportFor(
          AiCliTransport.acp,
        ),
        AiCliTransport.headlessPrompt,
      );
      expect(
        AiCliProvider.acp.capabilities.fallbackTransportFor(AiCliTransport.acp),
        isNull,
      );
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

    test(
      'provider slash command defaults stay conservative for flaky CLIs',
      () {
        expect(
          AiCliProvider.claude.capabilities.composerSlashCommands,
          containsAll(const <String>['/help', '/model']),
        );
        expect(AiCliProvider.codex.capabilities.composerSlashCommands, isEmpty);
      },
    );

    test('interactive transports requiring TTY are flagged conservatively', () {
      expect(AiCliProvider.claude.capabilities.requiresPty, isTrue);
      expect(AiCliProvider.codex.capabilities.requiresPty, isTrue);
      expect(AiCliProvider.opencode.capabilities.requiresPty, isFalse);
      expect(AiCliProvider.copilot.capabilities.requiresPty, isFalse);
    });

    test('ACP presets only include actual ACP launch commands', () {
      final copilotPreset = knownAcpClientPresets.firstWhere(
        (preset) => preset.id == 'copilot',
      );
      expect(copilotPreset.command, contains('--acp'));
      expect(copilotPreset.command, contains('--allow-all-tools'));

      final opencodePreset = knownAcpClientPresets.firstWhere(
        (preset) => preset.id == 'opencode',
      );
      expect(opencodePreset.command, 'opencode acp');

      final geminiPreset = knownAcpClientPresets.firstWhere(
        (preset) => preset.id == 'gemini',
      );
      expect(geminiPreset.command, 'gemini --acp');

      final claudeAdapterPreset = knownAcpClientPresets.firstWhere(
        (preset) => preset.id == 'claude-acp',
      );
      expect(claudeAdapterPreset.command, 'acp-adapter --adapter claude');

      final codexAdapterPreset = knownAcpClientPresets.firstWhere(
        (preset) => preset.id == 'codex-acp',
      );
      expect(codexAdapterPreset.command, 'acp-adapter --adapter codex');
    });
  });
}
