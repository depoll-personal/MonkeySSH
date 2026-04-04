// ignore_for_file: public_member_api_docs

import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monkeyssh/domain/services/local_terminal_ai_managed_model_service.dart';
import 'package:monkeyssh/domain/services/local_terminal_ai_platform_service.dart';
import 'package:monkeyssh/domain/services/local_terminal_ai_service.dart';
import 'package:monkeyssh/domain/services/local_terminal_ai_settings_service.dart';

void main() {
  group('LocalTerminalAiService', () {
    test('uses managed Gemma 4 when it is ready for suggestions', () async {
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
        managedModelCoordinator: managedModelCoordinator,
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
            fileType: ModelFileType.task,
            fileName: 'gemma-4-E2B-it.litertlm',
          ),
        ),
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
      'surfaces a helpful managed-download message when no runtime is ready',
      () async {
        final service = LocalTerminalAiService(
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
              contains(
                'Managed Gemma 4 download is not available on this platform',
              ),
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
            fileType: ModelFileType.task,
            fileName: 'gemma-4-E2B-it.litertlm',
          ),
        ),
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
            fileType: ModelFileType.task,
            fileName: 'gemma-4-E2B-it.litertlm',
          ),
        ),
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
          fileType: ModelFileType.task,
          fileName: 'gemma-4-E2B-it.litertlm',
        ),
      );
      final service = LocalTerminalAiService(
        managedModelCoordinator: managedModelCoordinator,
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
