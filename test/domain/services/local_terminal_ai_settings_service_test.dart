import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monkeyssh/data/database/database.dart';
import 'package:monkeyssh/domain/services/local_terminal_ai_managed_model_service.dart';
import 'package:monkeyssh/domain/services/local_terminal_ai_platform_service.dart';
import 'package:monkeyssh/domain/services/local_terminal_ai_settings_service.dart';
import 'package:monkeyssh/domain/services/settings_service.dart';

void main() {
  test('managed Gemma 4 download uses LiteRT-LM on desktop', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    const settings = LocalTerminalAiSettings(enabled: true);

    final spec = localTerminalAiManagedModelSpecForSettings(settings);

    expect(spec, isNotNull);
    expect(spec!.fileName, 'gemma-4-E2B-it.litertlm');
    expect(spec.url, contains('gemma-4-E2B-it.litertlm'));
    expect(spec.fileType, ModelFileType.litertlm);
    expect(spec.preferredBackend, isNull);
  });

  test('managed Gemma 3n download uses task format on iOS', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    const settings = LocalTerminalAiSettings(enabled: true);

    final spec = localTerminalAiManagedModelSpecForSettings(settings);

    expect(spec, isNotNull);
    expect(spec!.modelId, 'gemma-3n-E2B-it');
    expect(spec.fileName, 'gemma-3n-E2B-it-int4.task');
    expect(spec.fileType, ModelFileType.task);
    expect(spec.requiresHuggingFaceToken, isTrue);
    expect(spec.preferredBackend, PreferredBackend.gpu);
  });

  test('managed Gemma 4 download uses LiteRT-LM on Android', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    const settings = LocalTerminalAiSettings(enabled: true);

    final spec = localTerminalAiManagedModelSpecForSettings(settings);

    expect(spec, isNotNull);
    expect(spec!.modelId, 'gemma-4-E2B-it');
    expect(spec.fileType, ModelFileType.litertlm);
    expect(spec.foregroundDownload, isTrue);
    expect(spec.preferredBackend, PreferredBackend.gpu);
  });

  test(
    'managed Gemma runtime falls back from gpu to cpu on startup errors',
    () async {
      const spec = LocalTerminalAiManagedModelSpec(
        modelId: 'gemma-4-E2B-it',
        displayName: 'Gemma 4 E2B',
        url: 'https://example.com/gemma-4-E2B-it.litertlm',
        fileType: ModelFileType.litertlm,
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
      fileType: ModelFileType.litertlm,
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
    'managed model does not auto-download when the assistant is disabled',
    () {
      const settings = LocalTerminalAiSettings(enabled: false);

      expect(
        shouldAutoSyncManagedLocalTerminalAiModel(settings: settings),
        isFalse,
      );
    },
  );

  test('managed model auto-downloads on iOS when the assistant is enabled', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    const settings = LocalTerminalAiSettings(enabled: true);

    expect(
      shouldAutoSyncManagedLocalTerminalAiModel(settings: settings),
      isTrue,
    );
    expect(
      shouldAutoVerifyManagedLocalTerminalAiModelInBackground(
        settings: settings,
      ),
      isTrue,
    );
  });

  test(
    'managed model auto-downloads on Android when the assistant is enabled',
    () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      const settings = LocalTerminalAiSettings(enabled: true);

      expect(
        shouldAutoSyncManagedLocalTerminalAiModel(settings: settings),
        isTrue,
      );
      expect(
        shouldAutoVerifyManagedLocalTerminalAiModelInBackground(
          settings: settings,
        ),
        isTrue,
      );
    },
  );

  test('managed Gemma runtime stays on cpu when already cpu-first', () async {
    const spec = LocalTerminalAiManagedModelSpec(
      modelId: 'gemma-4-E2B-it',
      displayName: 'Gemma 4 E2B',
      url: 'https://example.com/gemma-4-E2B-it.litertlm',
      fileType: ModelFileType.litertlm,
      fileName: 'gemma-4-E2B-it.litertlm',
      preferredBackend: PreferredBackend.cpu,
    );
    final attemptedBackends = <PreferredBackend?>[];

    final result = await runWithManagedGemmaBackendFallback<PreferredBackend?>(
      spec: spec,
      operation: (preferredBackend) async {
        attemptedBackends.add(preferredBackend);
        return preferredBackend;
      },
    );

    expect(result, PreferredBackend.cpu);
    expect(attemptedBackends, <PreferredBackend?>[PreferredBackend.cpu]);
  });

  test('user toggle is not overwritten by delayed settings init', () async {
    final initialEnabled = Completer<bool>();
    final settingsService = _FakeSettingsService(initialEnabled.future);
    final platformService = _FakeLocalTerminalAiPlatformService();
    final managedController = _FakeLocalTerminalAiManagedModelController();
    final container = ProviderContainer(
      overrides: [
        settingsServiceProvider.overrideWithValue(settingsService),
        localTerminalAiPlatformServiceProvider.overrideWithValue(
          platformService,
        ),
        localTerminalAiManagedModelProvider.overrideWith(
          () => managedController,
        ),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(settingsService.close);

    expect(container.read(localTerminalAiSettingsProvider).enabled, isFalse);

    await Future<void>.delayed(Duration.zero);
    await container
        .read(localTerminalAiSettingsProvider.notifier)
        .setEnabled(enabled: true);

    initialEnabled.complete(false);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(container.read(localTerminalAiSettingsProvider).enabled, isTrue);
    expect(settingsService.storedEnabled, isTrue);
  });

  test('runtime sync fetches runtime info once per toggle', () async {
    final settingsService = _FakeSettingsService(Future<bool>.value(false));
    final platformService = _FakeLocalTerminalAiPlatformService();
    final managedController = _FakeLocalTerminalAiManagedModelController();
    final container = ProviderContainer(
      overrides: [
        settingsServiceProvider.overrideWithValue(settingsService),
        localTerminalAiPlatformServiceProvider.overrideWithValue(
          platformService,
        ),
        localTerminalAiManagedModelProvider.overrideWith(
          () => managedController,
        ),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(settingsService.close);

    container.read(localTerminalAiSettingsProvider);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    platformService.getRuntimeInfoCallCount = 0;
    managedController.syncCalls.clear();

    await container
        .read(localTerminalAiSettingsProvider.notifier)
        .setEnabled(enabled: true);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(platformService.getRuntimeInfoCallCount, 1);
    expect(managedController.syncCalls, hasLength(1));
    expect(managedController.syncCalls.single.settings.enabled, isTrue);
  });
}

class _FakeSettingsService extends SettingsService {
  factory _FakeSettingsService(Future<bool> initialEnabled) {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    return _FakeSettingsService._(database, initialEnabled);
  }

  _FakeSettingsService._(this._database, this._initialEnabled)
    : super(_database);

  final AppDatabase _database;
  final Future<bool> _initialEnabled;
  bool storedEnabled = false;
  bool _didReadInitialValue = false;

  Future<void> close() => _database.close();

  @override
  Future<bool> getBool(String key, {bool defaultValue = false}) async {
    if (key == SettingKeys.localTerminalAiEnabled && !_didReadInitialValue) {
      _didReadInitialValue = true;
      return _initialEnabled;
    }
    return storedEnabled;
  }

  @override
  Future<void> setBool(String key, {required bool value}) async {
    if (key == SettingKeys.localTerminalAiEnabled) {
      storedEnabled = value;
      return;
    }
    await super.setBool(key, value: value);
  }
}

class _FakeLocalTerminalAiPlatformService
    extends LocalTerminalAiPlatformService {
  int getRuntimeInfoCallCount = 0;

  @override
  Future<LocalTerminalAiRuntimeInfo> getRuntimeInfo() async {
    getRuntimeInfoCallCount += 1;
    return const LocalTerminalAiRuntimeInfo.unsupported();
  }
}

class _FakeLocalTerminalAiManagedModelController
    extends LocalTerminalAiManagedModelController {
  final List<
    ({
      LocalTerminalAiSettings settings,
      LocalTerminalAiRuntimeInfo? runtimeInfo,
    })
  >
  syncCalls = [];

  @override
  LocalTerminalAiManagedModelState build() =>
      const LocalTerminalAiManagedModelState.idle();

  @override
  Future<LocalTerminalAiManagedModelSpec?> ensureReadyFor(
    LocalTerminalAiSettings settings,
  ) async => null;

  @override
  Future<void> retry(LocalTerminalAiSettings settings) async {}

  @override
  Future<void> sync(
    LocalTerminalAiSettings settings, {
    LocalTerminalAiRuntimeInfo? runtimeInfo,
  }) async {
    syncCalls.add((settings: settings, runtimeInfo: runtimeInfo));
  }
}
