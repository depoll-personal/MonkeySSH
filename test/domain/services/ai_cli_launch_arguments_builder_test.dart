// ignore_for_file: public_member_api_docs

import 'package:flutter_test/flutter_test.dart';
import 'package:monkeyssh/domain/models/ai_cli_provider.dart';
import 'package:monkeyssh/domain/services/ai_cli_launch_arguments_builder.dart';
import 'package:monkeyssh/domain/services/ai_cli_session_preferences.dart';

void main() {
  group('AiCliLaunchArgumentsBuilder', () {
    const builder = AiCliLaunchArgumentsBuilder();

    test(
      'builds Claude persistent launch arguments with resume and steering',
      () {
        const preferences = AiCliSessionPreferences(
          providerSessionId: 'session-123',
          modelId: 'sonnet',
          systemPrompt: 'Be concise',
          appendSystemPrompt: 'Always explain diffs.',
        );

        final arguments = builder.buildPersistentLaunchArguments(
          provider: AiCliProvider.claude,
          preferences: preferences,
          resumedSession: true,
        );

        expect(
          arguments,
          equals(const <String>[
            '--resume',
            'session-123',
            '--model',
            'sonnet',
            '--system-prompt',
            'Be concise',
            '--append-system-prompt',
            'Always explain diffs.',
          ]),
        );
      },
    );

    test(
      'builds Codex persistent launch arguments with inline-friendly flags',
      () {
        const preferences = AiCliSessionPreferences(
          providerSessionId: 'codex-session',
          modelId: 'gpt-5',
          modeId: 'on-request',
        );

        final arguments = builder.buildPersistentLaunchArguments(
          provider: AiCliProvider.codex,
          preferences: preferences,
          resumedSession: true,
        );

        expect(
          arguments,
          equals(const <String>[
            'resume',
            'codex-session',
            '--no-alt-screen',
            '--model',
            'gpt-5',
            '--ask-for-approval',
            'on-request',
          ]),
        );
      },
    );

    test(
      'builds Gemini prompt arguments with resume, model, and approval mode',
      () {
        const preferences = AiCliSessionPreferences(
          providerSessionId: 'latest',
          modelId: 'gemini-2.5-pro',
          modeId: 'plan',
        );

        final arguments = builder.buildHeadlessPromptArguments(
          provider: AiCliProvider.gemini,
          preferences: preferences,
          prompt: 'Summarize the repo',
        );

        expect(
          arguments,
          containsAllInOrder(const <String>[
            '--resume',
            'latest',
            '--prompt',
            'Summarize the repo',
            '--output-format',
            'stream-json',
            '--model',
            'gemini-2.5-pro',
            '--approval-mode',
            'plan',
          ]),
        );
      },
    );

    test('rejects headless prompt arguments for ACP custom clients', () {
      expect(
        () => builder.buildHeadlessPromptArguments(
          provider: AiCliProvider.acp,
          preferences: const AiCliSessionPreferences(),
          prompt: 'Hello',
        ),
        throwsUnsupportedError,
      );
    });
  });
}
