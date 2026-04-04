import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
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
    expect(spec.fileType, ModelFileType.task);
    expect(spec.preferredBackend, PreferredBackend.gpu);
  });

  test('managed Gemma 4 uses LiteRT-LM on iOS', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    const settings = LocalTerminalAiSettings(enabled: true);

    final spec = localTerminalAiManagedGemma4SpecForSettings(settings);

    expect(spec, isNotNull);
    expect(spec!.fileName, 'gemma-4-E2B-it.litertlm');
    expect(spec.url, contains('7fa1d78473894f7e736a21d920c3aa80f950c0db'));
    expect(spec.preferredBackend, PreferredBackend.gpu);
  });

  test('managed Gemma 4 auto-downloads whenever the assistant is enabled', () {
    const settings = LocalTerminalAiSettings(enabled: true);

    expect(shouldAutoSyncManagedGemma4(settings: settings), isTrue);
  });

  test(
    'managed Gemma runtime falls back from gpu to cpu on startup errors',
    () async {
      const spec = LocalTerminalAiManagedModelSpec(
        modelId: 'gemma-4-E2B-it',
        displayName: 'Gemma 4 E2B',
        url: 'https://example.com/gemma-4-E2B-it.litertlm',
        fileType: ModelFileType.task,
        fileName: 'gemma-4-E2B-it.litertlm',
        preferredBackend: PreferredBackend.gpu,
      );
      final attemptedBackends = <PreferredBackend?>[];

      final result = await runWithManagedGemmaBackendFallback<PreferredBackend?>(
        spec: spec,
        operation: (preferredBackend) async {
          attemptedBackends.add(preferredBackend);
          if (preferredBackend == PreferredBackend.gpu) {
            throw Exception(
              'PlatformException(failedToInitializeEngine, INTERNAL: RET_CHECK failure model Error building tflite model, null, null)',
            );
          }
          return preferredBackend;
        },
      );

      expect(result, PreferredBackend.cpu);
      expect(attemptedBackends, <PreferredBackend?>[
        PreferredBackend.gpu,
        PreferredBackend.cpu,
      ]);
    },
  );

  test('managed Gemma runtime does not retry non-startup errors', () async {
    const spec = LocalTerminalAiManagedModelSpec(
      modelId: 'gemma-4-E2B-it',
      displayName: 'Gemma 4 E2B',
      url: 'https://example.com/gemma-4-E2B-it.litertlm',
      fileType: ModelFileType.task,
      fileName: 'gemma-4-E2B-it.litertlm',
      preferredBackend: PreferredBackend.gpu,
    );
    final attemptedBackends = <PreferredBackend?>[];

    await expectLater(
      () => runWithManagedGemmaBackendFallback<void>(
        spec: spec,
        operation: (preferredBackend) async {
          attemptedBackends.add(preferredBackend);
          throw Exception('network timeout');
        },
      ),
      throwsA(isA<Exception>()),
    );

    expect(attemptedBackends, <PreferredBackend?>[PreferredBackend.gpu]);
  });

  test(
    'managed Gemma 4 does not auto-download when the assistant is disabled',
    () {
      const settings = LocalTerminalAiSettings(enabled: false);

      expect(shouldAutoSyncManagedGemma4(settings: settings), isFalse);
    },
  );
}
