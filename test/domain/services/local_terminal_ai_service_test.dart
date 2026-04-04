// ignore_for_file: public_member_api_docs

import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monkeyssh/domain/services/local_terminal_ai_managed_model_service.dart';
import 'package:monkeyssh/domain/services/local_terminal_ai_platform_service.dart';
import 'package:monkeyssh/domain/services/local_terminal_ai_service.dart';
import 'package:monkeyssh/domain/services/local_terminal_ai_settings_service.dart';

void main() {
  group('LocalTerminalAiService', () {
    test(
      'uses Apple Foundation Models when the native runtime is ready for suggestions',
      () async {
        final platformService = _FakePlatformService(
          runtimeInfo: const LocalTerminalAiRuntimeInfo(
            provider: LocalTerminalAiPlatformProvider.appleFoundationModels,
            supportedPlatform: true,
            available: true,
            statusMessage: 'Apple Intelligence is ready on this device.',
            modelName: 'Apple Intelligence',
          ),
          response: 'pwd || Print directory',
        );
        final fallback = _FakeFallbackRuntime(response: 'unused');
        final managedModelCoordinator = _FakeManagedModelCoordinator(
          managedModel: const LocalTerminalAiManagedModelSpec(
            modelId: 'gemma-4-E2B-it',
            displayName: 'Gemma 4 E2B',
            url: 'https://example.com/gemma-4-E2B-it.litertlm',
            fileType: ModelFileType.litertlm,
            fileName: 'gemma-4-E2B-it.litertlm',
          ),
        );
        final service = LocalTerminalAiService(
          managedModelCoordinator: managedModelCoordinator,
          platformService: platformService,
          fallbackRuntime: fallback,
        );

        final suggestions = await service.suggestCommands(
          settings: const LocalTerminalAiSettings(enabled: true),
          taskDescription: 'show current directory',
          hostLabel: 'prod',
        );

        expect(platformService.prepareCallCount, 0);
        expect(platformService.generateCallCount, 1);
        expect(managedModelCoordinator.ensureReadyCallCount, 0);
        expect(fallback.generateCallCount, 0);
        expect(suggestions.single.command, 'pwd');
      },
    );

    test(
      'prepares Gemini Nano before generating when Android support exists',
      () async {
        final platformService = _FakePlatformService(
          runtimeInfo: const LocalTerminalAiRuntimeInfo(
            provider: LocalTerminalAiPlatformProvider.androidAiCore,
            supportedPlatform: true,
            available: false,
            statusMessage:
                'Gemini Nano is supported here but still downloading or preparing.',
          ),
          response: 'pwd || Print directory',
        );
        final fallback = _FakeFallbackRuntime(response: 'unused');
        final managedModelCoordinator = _FakeManagedModelCoordinator();
        final service = LocalTerminalAiService(
          managedModelCoordinator: managedModelCoordinator,
          platformService: platformService,
          fallbackRuntime: fallback,
        );

        final suggestions = await service.suggestCommands(
          settings: const LocalTerminalAiSettings(enabled: true),
          taskDescription: 'show current directory',
          hostLabel: 'prod',
        );

        expect(platformService.prepareCallCount, 1);
        expect(platformService.generateCallCount, 1);
        expect(managedModelCoordinator.ensureReadyCallCount, 0);
        expect(fallback.generateCallCount, 0);
        expect(suggestions.single.command, 'pwd');
      },
    );

    test('uses managed Gemma 4 when it is ready for suggestions', () async {
      final fallback = _FakeFallbackRuntime(response: 'pwd || Print directory');
      final managedModelCoordinator = _FakeManagedModelCoordinator(
        managedModel: const LocalTerminalAiManagedModelSpec(
          modelId: 'gemma-4-E2B-it',
          displayName: 'Gemma 4 E2B',
          url: 'https://example.com/gemma-4-E2B-it.litertlm',
          fileType: ModelFileType.litertlm,
          fileName: 'gemma-4-E2B-it.litertlm',
        ),
      );
      final service = LocalTerminalAiService(
        managedModelCoordinator: managedModelCoordinator,
        platformService: _FakePlatformService.unsupported(),
        fallbackRuntime: fallback,
      );

      final suggestions = await service.suggestCommands(
        settings: const LocalTerminalAiSettings(enabled: true),
        taskDescription: 'show current directory',
        hostLabel: 'prod',
      );

      expect(managedModelCoordinator.ensureReadyCallCount, 1);
      expect(fallback.generateCallCount, 1);
      expect(fallback.lastManagedModel?.modelId, 'gemma-4-E2B-it');
      expect(fallback.lastMaxTokens, 256);
      expect(suggestions.single.command, 'pwd');
    });

    test('uses managed Gemma 4 when it is ready for completions', () async {
      final fallback = _FakeFallbackRuntime(response: 'ls -la');
      final service = LocalTerminalAiService(
        managedModelCoordinator: _FakeManagedModelCoordinator(
          managedModel: const LocalTerminalAiManagedModelSpec(
            modelId: 'gemma-4-E2B-it',
            displayName: 'Gemma 4 E2B',
            url: 'https://example.com/gemma-4-E2B-it.litertlm',
            fileType: ModelFileType.litertlm,
            fileName: 'gemma-4-E2B-it.litertlm',
          ),
        ),
        platformService: _FakePlatformService.unsupported(),
        fallbackRuntime: fallback,
      );

      final completion = await service.completeCurrentCommand(
        settings: const LocalTerminalAiSettings(enabled: true),
        currentTerminalLine: 'ls',
        hostLabel: 'prod',
      );

      expect(completion.suffix, ' -la');
      expect(completion.preview, 'ls -la');
      expect(fallback.lastMaxTokens, 256);
    });

    test(
      'surfaces a helpful platform message when no runtime is ready',
      () async {
        final service = LocalTerminalAiService(
          managedModelCoordinator: _FakeManagedModelCoordinator(),
          platformService: _FakePlatformService.unsupported(),
          fallbackRuntime: _FakeFallbackRuntime(response: 'unused'),
        );

        await expectLater(
          service.suggestCommands(
            settings: const LocalTerminalAiSettings(enabled: true),
            taskDescription: 'list files',
            hostLabel: 'prod',
          ),
          throwsA(
            isA<LocalTerminalAiConfigurationException>().having(
              (error) => error.message,
              'message',
              'This platform does not expose a built-in on-device language model.',
            ),
          ),
        );
      },
    );

    test('surfaces a helpful managed runtime startup message', () async {
      final service = LocalTerminalAiService(
        managedModelCoordinator: _FakeManagedModelCoordinator(
          managedModel: const LocalTerminalAiManagedModelSpec(
            modelId: 'gemma-4-E2B-it',
            displayName: 'Gemma 4 E2B',
            url: 'https://example.com/gemma-4-E2B-it.litertlm',
            fileType: ModelFileType.litertlm,
            fileName: 'gemma-4-E2B-it.litertlm',
          ),
        ),
        platformService: _FakePlatformService.unsupported(),
        fallbackRuntime: _FakeFallbackRuntime(
          response: 'unused',
          error: Exception(
            'PlatformException(LiteRtLmJniException, Failed to invoke the compiled model, null, null)',
          ),
        ),
      );

      await expectLater(
        service.suggestCommands(
          settings: const LocalTerminalAiSettings(enabled: true),
          taskDescription: 'list files',
          hostLabel: 'prod',
        ),
        throwsA(
          isA<LocalTerminalAiConfigurationException>().having(
            (error) => error.message,
            'message',
            contains('installed but could not start on this device'),
          ),
        ),
      );
    });

    test('surfaces a helpful iOS engine startup message', () async {
      final service = LocalTerminalAiService(
        managedModelCoordinator: _FakeManagedModelCoordinator(
          managedModel: const LocalTerminalAiManagedModelSpec(
            modelId: 'gemma-4-E2B-it',
            displayName: 'Gemma 4 E2B',
            url: 'https://example.com/gemma-4-E2B-it.litertlm',
            fileType: ModelFileType.litertlm,
            fileName: 'gemma-4-E2B-it.litertlm',
          ),
        ),
        platformService: _FakePlatformService.unsupported(),
        fallbackRuntime: _FakeFallbackRuntime(
          response: 'unused',
          error: Exception(
            'PlatformException(failedToInitializeEngine, INTERNAL: RET_CHECK failure model Error building tflite model, null, null)',
          ),
        ),
      );

      await expectLater(
        service.suggestCommands(
          settings: const LocalTerminalAiSettings(enabled: true),
          taskDescription: 'list files',
          hostLabel: 'prod',
        ),
        throwsA(
          isA<LocalTerminalAiConfigurationException>().having(
            (error) => error.message,
            'message',
            contains('installed but could not start on this device'),
          ),
        ),
      );
    });

    test('does not try to run when the assistant is disabled', () async {
      final fallback = _FakeFallbackRuntime(response: 'pwd || Print directory');
      final managedModelCoordinator = _FakeManagedModelCoordinator(
        managedModel: const LocalTerminalAiManagedModelSpec(
          modelId: 'gemma-4-E2B-it',
          displayName: 'Gemma 4 E2B',
          url: 'https://example.com/gemma-4-E2B-it.litertlm',
          fileType: ModelFileType.litertlm,
          fileName: 'gemma-4-E2B-it.litertlm',
        ),
      );
      final service = LocalTerminalAiService(
        managedModelCoordinator: managedModelCoordinator,
        platformService: _FakePlatformService.unsupported(),
        fallbackRuntime: fallback,
      );

      await expectLater(
        service.suggestCommands(
          settings: const LocalTerminalAiSettings(enabled: false),
          taskDescription: 'show current directory',
          hostLabel: 'prod',
        ),
        throwsA(
          isA<LocalTerminalAiConfigurationException>().having(
            (error) => error.message,
            'message',
            contains(
              'Enable the on-device terminal assistant in Settings first',
            ),
          ),
        ),
      );

      expect(managedModelCoordinator.ensureReadyCallCount, 0);
      expect(fallback.generateCallCount, 0);
    });
  });
}

class _FakePlatformService extends LocalTerminalAiPlatformService {
  _FakePlatformService({required this.runtimeInfo, this.response});

  _FakePlatformService.unsupported({
    String statusMessage =
        'This platform does not expose a built-in on-device language model.',
  }) : this(
         runtimeInfo: LocalTerminalAiRuntimeInfo.unsupported(
           statusMessage: statusMessage,
         ),
       );

  final LocalTerminalAiRuntimeInfo runtimeInfo;
  final String? response;
  int prepareCallCount = 0;
  int generateCallCount = 0;

  @override
  Future<LocalTerminalAiRuntimeInfo> getRuntimeInfo() async => runtimeInfo;

  @override
  Future<void> prepareRuntime() async => prepareCallCount += 1;

  @override
  Future<String> generateText({
    required String prompt,
    required int maxTokens,
  }) async {
    generateCallCount += 1;
    return response ?? 'pwd || Print directory';
  }
}

class _FakeFallbackRuntime implements LocalTerminalAiFallbackRuntime {
  _FakeFallbackRuntime({required this.response, this.error});

  final String response;
  final Exception? error;
  int generateCallCount = 0;
  int? lastMaxTokens;
  LocalTerminalAiManagedModelSpec? lastManagedModel;

  @override
  Future<String> generateText({
    required String prompt,
    required int maxTokens,
    required LocalTerminalAiManagedModelSpec managedModel,
  }) async {
    generateCallCount += 1;
    lastManagedModel = managedModel;
    lastMaxTokens = maxTokens;
    if (error case final error?) {
      throw error;
    }
    return response;
  }
}

class _FakeManagedModelCoordinator
    implements LocalTerminalAiManagedModelCoordinator {
  _FakeManagedModelCoordinator({this.managedModel});

  final LocalTerminalAiManagedModelSpec? managedModel;
  int ensureReadyCallCount = 0;

  @override
  Future<LocalTerminalAiManagedModelSpec?> ensureReadyFor(
    LocalTerminalAiSettings settings,
  ) async {
    ensureReadyCallCount += 1;
    return managedModel;
  }

  @override
  Future<void> retry(LocalTerminalAiSettings settings) async {}

  @override
  Future<void> sync(
    LocalTerminalAiSettings settings, {
    LocalTerminalAiRuntimeInfo? runtimeInfo,
  }) async {}
}
