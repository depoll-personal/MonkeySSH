// ignore_for_file: public_member_api_docs

import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_test/flutter_test.dart';

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
        fallbackRuntime: fallback,
      );

      final suggestions = await service.suggestCommands(
        settings: const LocalTerminalAiSettings(
          enabled: true,
          modelType: ModelType.gemmaIt,
          preferNativeRuntime: true,
        ),
        taskDescription: 'list files',
        hostLabel: 'prod',
      );

      expect(platform.generateCallCount, 1);
      expect(fallback.generateCallCount, 0);
      expect(suggestions.single.command, 'ls');
    });

    test(
      'falls back to the configured local model when native is unavailable',
      () async {
        final platform = _FakeLocalTerminalAiPlatformService(
          runtimeInfo: const LocalTerminalAiRuntimeInfo(
            provider: LocalTerminalAiPlatformProvider.androidAiCore,
            supportedPlatform: true,
            available: false,
            statusMessage: 'Gemini Nano is not ready on this device.',
          ),
          response: 'unused',
        );
        final fallback = _FakeFallbackRuntime(
          response: 'pwd || Print directory',
        );
        final service = LocalTerminalAiService(
          platformRuntime: platform,
          fallbackRuntime: fallback,
        );

        final suggestions = await service.suggestCommands(
          settings: const LocalTerminalAiSettings(
            enabled: true,
            modelType: ModelType.gemmaIt,
            preferNativeRuntime: true,
            modelPath: '/models/gemma.task',
          ),
          taskDescription: 'show current directory',
          hostLabel: 'prod',
        );

        expect(platform.generateCallCount, 0);
        expect(fallback.generateCallCount, 1);
        expect(suggestions.single.command, 'pwd');
      },
    );

    test(
      'uses the fallback runtime when native preference is disabled',
      () async {
        final platform = _FakeLocalTerminalAiPlatformService(
          runtimeInfo: const LocalTerminalAiRuntimeInfo(
            provider: LocalTerminalAiPlatformProvider.appleFoundationModels,
            supportedPlatform: true,
            available: true,
            statusMessage: 'Apple Foundation Models is ready.',
          ),
          response: 'unused',
        );
        final fallback = _FakeFallbackRuntime(response: 'echo ok || Print ok');
        final service = LocalTerminalAiService(
          platformRuntime: platform,
          fallbackRuntime: fallback,
        );

        final suggestions = await service.suggestCommands(
          settings: const LocalTerminalAiSettings(
            enabled: true,
            modelType: ModelType.gemmaIt,
            preferNativeRuntime: false,
            modelPath: '/models/gemma.task',
          ),
          taskDescription: 'print ok',
          hostLabel: 'prod',
        );

        expect(platform.generateCallCount, 0);
        expect(fallback.generateCallCount, 1);
        expect(suggestions.single.command, 'echo ok');
      },
    );

    test(
      'surfaces a helpful fallback message when no runtime is ready',
      () async {
        final platform = _FakeLocalTerminalAiPlatformService(
          runtimeInfo: const LocalTerminalAiRuntimeInfo(
            provider: LocalTerminalAiPlatformProvider.androidAiCore,
            supportedPlatform: true,
            available: false,
            statusMessage: 'Gemini Nano is not ready on this device.',
          ),
          response: 'unused',
        );
        final service = LocalTerminalAiService(
          platformRuntime: platform,
          fallbackRuntime: _FakeFallbackRuntime(response: 'unused'),
        );

        await expectLater(
          service.suggestCommands(
            settings: const LocalTerminalAiSettings(
              enabled: true,
              modelType: ModelType.gemmaIt,
              preferNativeRuntime: true,
            ),
            taskDescription: 'list files',
            hostLabel: 'prod',
          ),
          throwsA(
            isA<LocalTerminalAiConfigurationException>().having(
              (error) => error.message,
              'message',
              contains('Select a local `.task` or `.litertlm` model file'),
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
        fallbackRuntime: _FakeFallbackRuntime(response: 'unused'),
      );

      final completion = await service.completeCurrentCommand(
        settings: const LocalTerminalAiSettings(
          enabled: true,
          modelType: ModelType.gemmaIt,
          preferNativeRuntime: true,
        ),
        currentTerminalLine: 'ls',
        hostLabel: 'prod',
      );

      expect(completion.suffix, ' -la');
      expect(completion.preview, 'ls -la');
    });
  });
}

class _FakeLocalTerminalAiPlatformService
    extends LocalTerminalAiPlatformService {
  _FakeLocalTerminalAiPlatformService({
    required this.runtimeInfo,
    required this.response,
  });

  final LocalTerminalAiRuntimeInfo runtimeInfo;
  final String response;
  int generateCallCount = 0;

  @override
  Future<LocalTerminalAiRuntimeInfo> getRuntimeInfo() async => runtimeInfo;

  @override
  Future<String> generateText({
    required String prompt,
    required int maxTokens,
  }) async {
    generateCallCount += 1;
    return response;
  }
}

class _FakeFallbackRuntime implements LocalTerminalAiFallbackRuntime {
  _FakeFallbackRuntime({required this.response});

  final String response;
  int generateCallCount = 0;

  @override
  Future<String> generateText({
    required LocalTerminalAiSettings settings,
    required String prompt,
    required int maxTokens,
  }) async {
    generateCallCount += 1;
    return response;
  }
}
