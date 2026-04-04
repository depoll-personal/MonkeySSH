import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monkeyssh/domain/services/local_terminal_ai_managed_model_service.dart';
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

  test('managed Gemma 4 auto-downloads whenever the assistant is enabled', () {
    const settings = LocalTerminalAiSettings(enabled: true);

    expect(shouldAutoSyncManagedGemma4(settings: settings), isTrue);
  });

  test(
    'managed Gemma 4 does not auto-download when the assistant is disabled',
    () {
      const settings = LocalTerminalAiSettings(enabled: false);

      expect(shouldAutoSyncManagedGemma4(settings: settings), isFalse);
    },
  );
}
