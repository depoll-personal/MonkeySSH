// ignore_for_file: public_member_api_docs

import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:monkeyssh/domain/services/local_terminal_ai_managed_model_service.dart';
import 'package:monkeyssh/domain/services/local_terminal_ai_platform_service.dart';
import 'package:monkeyssh/domain/services/local_terminal_ai_service.dart';
import 'package:monkeyssh/domain/services/local_terminal_ai_settings_service.dart';

void main() {
  group('LocalTerminalAiService', () {
    test('prefers the native runtime when it is available', () async {
      final platform = _FakeLocalTerminalAiPlatformService(
        runtimeInfo: const LocalTerminalAiRuntimeInfo(
          provider: LocalTerminalAiPlatformProvider.appleFoundationModels,
          supportedPlatform: true,
          available: true,
          statusMessage: 'Apple Foundation Models is ready.',
          modelName: 'Apple Intelligence',
        ),
        response: 'ls || List files',
      );
      final fallback = _FakeFallbackRuntime(response: 'pwd || Print directory');
      final service = LocalTerminalAiService(
        platformRuntime: platform,
        managedModelCoordinator: _FakeManagedModelCoordinator(),
        fallbackRuntime: fallback,
      );

      final suggestions = await service.suggestCommands(
        settings: const LocalTerminalAiSettings(enabled: true),
        taskDescription: 'list files',
        hostLabel: 'prod',
      );

      expect(platform.generateCallCount, 1);
      expect(fallback.generateCallCount, 0);
      expect(suggestions.single.command, 'ls');
    });

    test('falls back to managed Gemma 4 when native is unavailable', () async {
      final platform = _FakeLocalTerminalAiPlatformService(
        runtimeInfo: const LocalTerminalAiRuntimeInfo(
          provider: LocalTerminalAiPlatformProvider.androidAiCore,
          supportedPlatform: false,
          available: false,
          statusMessage:
              'Android AI Core prompt generation is unavailable on this device.',
        ),
        response: 'unused',
      );
      final fallback = _FakeFallbackRuntime(response: 'pwd || Print directory');
      final service = LocalTerminalAiService(
        platformRuntime: platform,
        managedModelCoordinator: _FakeManagedModelCoordinator(
          managedModel: const LocalTerminalAiManagedModelSpec(
            modelId: 'gemma-4-E2B-it',
            displayName: 'Gemma 4 E2B',
            url: 'https://example.com/gemma-4-E2B-it.litertlm',
            fileType: ModelFileType.task,
            fileName: 'gemma-4-E2B-it.litertlm',
          ),
        ),
        fallbackRuntime: fallback,
      );

      final suggestions = await service.suggestCommands(
        settings: const LocalTerminalAiSettings(enabled: true),
        taskDescription: 'show current directory',
        hostLabel: 'prod',
      );

      expect(platform.generateCallCount, 0);
      expect(fallback.generateCallCount, 1);
      expect(fallback.lastManagedModel?.modelId, 'gemma-4-E2B-it');
      expect(suggestions.single.command, 'pwd');
    });

    test(
      'tries the native runtime while Android AI Core is still preparing',
      () async {
        final platform = _FakeLocalTerminalAiPlatformService(
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
        final managedModelCoordinator = _FakeManagedModelCoordinator(
          managedModel: const LocalTerminalAiManagedModelSpec(
            modelId: 'gemma-4-E2B-it',
            displayName: 'Gemma 4 E2B',
            url: 'https://example.com/gemma-4-E2B-it.litertlm',
            fileType: ModelFileType.task,
            fileName: 'gemma-4-E2B-it.litertlm',
          ),
        );
        final service = LocalTerminalAiService(
          platformRuntime: platform,
          managedModelCoordinator: managedModelCoordinator,
          fallbackRuntime: fallback,
        );

        final suggestions = await service.suggestCommands(
          settings: const LocalTerminalAiSettings(enabled: true),
          taskDescription: 'show current directory',
          hostLabel: 'prod',
        );

        expect(platform.generateCallCount, 1);
        expect(managedModelCoordinator.ensureReadyCallCount, 0);
        expect(fallback.generateCallCount, 0);
        expect(suggestions.single.command, 'pwd');
      },
    );

    test('falls back to managed Gemma 4 if native provisioning fails', () async {
      final platform = _FakeLocalTerminalAiPlatformService(
        runtimeInfo: const LocalTerminalAiRuntimeInfo(
          provider: LocalTerminalAiPlatformProvider.androidAiCore,
          supportedPlatform: true,
          available: false,
          statusMessage:
              'Gemini Nano is supported here but still downloading or preparing.',
        ),
        response: 'unused',
        generateError: const LocalTerminalAiPlatformException(
          'Android AI Core preparation failed.',
        ),
      );
      final fallback = _FakeFallbackRuntime(response: 'pwd || Print directory');
      final service = LocalTerminalAiService(
        platformRuntime: platform,
        managedModelCoordinator: _FakeManagedModelCoordinator(
          managedModel: const LocalTerminalAiManagedModelSpec(
            modelId: 'gemma-4-E2B-it',
            displayName: 'Gemma 4 E2B',
            url: 'https://example.com/gemma-4-E2B-it.litertlm',
            fileType: ModelFileType.task,
            fileName: 'gemma-4-E2B-it.litertlm',
          ),
        ),
        fallbackRuntime: fallback,
      );

      final suggestions = await service.suggestCommands(
        settings: const LocalTerminalAiSettings(enabled: true),
        taskDescription: 'show current directory',
        hostLabel: 'prod',
      );

      expect(platform.generateCallCount, 1);
      expect(fallback.generateCallCount, 1);
      expect(suggestions.single.command, 'pwd');
    });

    test(
      'surfaces a helpful managed-download message when no runtime is ready',
      () async {
        final platform = _FakeLocalTerminalAiPlatformService(
          runtimeInfo: const LocalTerminalAiRuntimeInfo(
            provider: LocalTerminalAiPlatformProvider.androidAiCore,
            supportedPlatform: false,
            available: false,
            statusMessage:
                'Android AI Core prompt generation is unavailable on this device.',
          ),
          response: 'unused',
        );
        final service = LocalTerminalAiService(
          platformRuntime: platform,
          managedModelCoordinator: _FakeManagedModelCoordinator(),
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
              contains('Gemma 4 download is not available on this platform'),
            ),
          ),
        );
      },
    );

    test('normalizes completion suffixes from the selected runtime', () async {
      final platform = _FakeLocalTerminalAiPlatformService(
        runtimeInfo: const LocalTerminalAiRuntimeInfo(
          provider: LocalTerminalAiPlatformProvider.appleFoundationModels,
          supportedPlatform: true,
          available: true,
          statusMessage: 'Apple Foundation Models is ready.',
        ),
        response: 'ls -la',
      );
      final service = LocalTerminalAiService(
        platformRuntime: platform,
        managedModelCoordinator: _FakeManagedModelCoordinator(),
        fallbackRuntime: _FakeFallbackRuntime(response: 'unused'),
      );

      final completion = await service.completeCurrentCommand(
        settings: const LocalTerminalAiSettings(enabled: true),
        currentTerminalLine: 'ls',
        hostLabel: 'prod',
      );

      expect(completion.suffix, ' -la');
      expect(completion.preview, 'ls -la');
    });

    test('uses the managed Gemma 4 fallback when it is ready', () async {
      final platform = _FakeLocalTerminalAiPlatformService(
        runtimeInfo: const LocalTerminalAiRuntimeInfo(
          provider: LocalTerminalAiPlatformProvider.androidAiCore,
          supportedPlatform: false,
          available: false,
          statusMessage:
              'Android AI Core prompt generation is unavailable on this device.',
        ),
        response: 'unused',
      );
      final fallback = _FakeFallbackRuntime(response: 'pwd || Print directory');
      final managedModelCoordinator = _FakeManagedModelCoordinator(
        managedModel: const LocalTerminalAiManagedModelSpec(
          modelId: 'gemma-4-E2B-it',
          displayName: 'Gemma 4 E2B',
          url: 'https://example.com/gemma-4-E2B-it.litertlm',
          fileType: ModelFileType.task,
          fileName: 'gemma-4-E2B-it.litertlm',
        ),
      );
      final service = LocalTerminalAiService(
        platformRuntime: platform,
        managedModelCoordinator: managedModelCoordinator,
        fallbackRuntime: fallback,
      );

      final suggestions = await service.suggestCommands(
        settings: const LocalTerminalAiSettings(enabled: true),
        taskDescription: 'show current directory',
        hostLabel: 'prod',
      );

      expect(platform.generateCallCount, 0);
      expect(managedModelCoordinator.ensureReadyCallCount, 1);
      expect(fallback.generateCallCount, 1);
      expect(fallback.lastManagedModel?.modelId, 'gemma-4-E2B-it');
      expect(suggestions.single.command, 'pwd');
    });
  });
}

class _FakeLocalTerminalAiPlatformService
    extends LocalTerminalAiPlatformService {
  _FakeLocalTerminalAiPlatformService({
    required this.runtimeInfo,
    required this.response,
    this.generateError,
  });

  final LocalTerminalAiRuntimeInfo runtimeInfo;
  final String response;
  final LocalTerminalAiPlatformException? generateError;
  int generateCallCount = 0;

  @override
  Future<LocalTerminalAiRuntimeInfo> getRuntimeInfo() async => runtimeInfo;

  @override
  Future<String> generateText({
    required String prompt,
    required int maxTokens,
  }) async {
    generateCallCount += 1;
    if (generateError case final error?) {
      throw error;
    }
    return response;
  }
}

class _FakeFallbackRuntime implements LocalTerminalAiFallbackRuntime {
  _FakeFallbackRuntime({required this.response});

  final String response;
  int generateCallCount = 0;
  LocalTerminalAiManagedModelSpec? lastManagedModel;

  @override
  Future<String> generateText({
    required String prompt,
    required int maxTokens,
    required LocalTerminalAiManagedModelSpec managedModel,
  }) async {
    generateCallCount += 1;
    lastManagedModel = managedModel;
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
