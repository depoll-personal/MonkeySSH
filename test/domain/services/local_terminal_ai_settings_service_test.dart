import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monkeyssh/domain/services/local_terminal_ai_managed_model_service.dart';
import 'package:monkeyssh/domain/services/local_terminal_ai_platform_service.dart';
import 'package:monkeyssh/domain/services/local_terminal_ai_settings_service.dart';

void main() {
  test('managed Gemma 4 download uses LiteRT-LM on Android', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    const settings = LocalTerminalAiSettings(enabled: true);

    final spec = localTerminalAiManagedGemma4SpecForSettings(settings);

    expect(spec, isNotNull);
    expect(spec!.fileName, 'gemma-4-E2B-it.litertlm');
    expect(spec.url, contains('gemma-4-E2B-it.litertlm'));
  });

  test('managed Gemma 4 download also applies on iOS', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    const settings = LocalTerminalAiSettings(enabled: true);

    final spec = localTerminalAiManagedGemma4SpecForSettings(settings);

    expect(spec, isNotNull);
    expect(spec!.fileName, 'gemma-4-E2B-it.litertlm');
  });

  test(
    'managed Gemma 4 does not auto-download while native runtime is supported',
    () {
      const settings = LocalTerminalAiSettings(enabled: true);
      const runtimeInfo = LocalTerminalAiRuntimeInfo(
        provider: LocalTerminalAiPlatformProvider.androidAiCore,
        supportedPlatform: true,
        available: false,
        statusMessage:
            'Gemini Nano is supported here but still downloading or preparing.',
      );

      expect(
        shouldAutoSyncManagedGemma4(
          settings: settings,
          runtimeInfo: runtimeInfo,
        ),
        isFalse,
      );
    },
  );

  test('managed Gemma 4 auto-downloads when no native runtime exists', () {
    const settings = LocalTerminalAiSettings(enabled: true);
    const runtimeInfo = LocalTerminalAiRuntimeInfo.unsupported();

    expect(
      shouldAutoSyncManagedGemma4(settings: settings, runtimeInfo: runtimeInfo),
      isTrue,
    );
  });
}
