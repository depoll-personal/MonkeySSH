// ignore_for_file: public_member_api_docs

import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monkeyssh/domain/services/local_terminal_ai_managed_model_service.dart';
import 'package:monkeyssh/domain/services/local_terminal_ai_platform_service.dart';
import 'package:monkeyssh/domain/services/local_terminal_ai_service.dart';
import 'package:monkeyssh/domain/services/local_terminal_ai_settings_service.dart';
import 'package:monkeyssh/presentation/widgets/terminal_ai_assistant_sheet.dart';

const _managedSpec = LocalTerminalAiManagedModelSpec(
  modelId: 'gemma-4-E2B-it',
  displayName: 'Gemma 4 E2B',
  url: 'https://example.com/gemma-4-E2B-it.litertlm',
  fileType: ModelFileType.litertlm,
  fileName: 'gemma-4-E2B-it.litertlm',
);

LocalTerminalAiSettings _settingsState = const LocalTerminalAiSettings(
  enabled: true,
);
LocalTerminalAiManagedModelState _managedModelState =
    const LocalTerminalAiManagedModelState.idle();
LocalTerminalAiRuntimeInfo _runtimeInfoState =
    const LocalTerminalAiRuntimeInfo.unsupported();

class _StaticLocalTerminalAiSettingsNotifier
    extends LocalTerminalAiSettingsNotifier {
  @override
  LocalTerminalAiSettings build() => _settingsState;

  @override
  Future<void> setEnabled({required bool enabled}) async {
    state = LocalTerminalAiSettings(enabled: enabled);
  }
}

class _StaticLocalTerminalAiManagedModelController
    extends LocalTerminalAiManagedModelController {
  @override
  LocalTerminalAiManagedModelState build() => _managedModelState;

  @override
  Future<LocalTerminalAiManagedModelSpec?> ensureReadyFor(
    LocalTerminalAiSettings settings,
  ) async => _managedModelState.spec;

  @override
  Future<void> retry(LocalTerminalAiSettings settings) async {}

  @override
  Future<void> sync(
    LocalTerminalAiSettings settings, {
    LocalTerminalAiRuntimeInfo? runtimeInfo,
  }) async {}
}

void main() {
  setUp(() {
    _settingsState = const LocalTerminalAiSettings(enabled: true);
    _managedModelState = const LocalTerminalAiManagedModelState.idle();
    _runtimeInfoState = const LocalTerminalAiRuntimeInfo.unsupported();
  });

  Future<void> pumpAssistantSheet(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localTerminalAiSettingsProvider.overrideWith(
            _StaticLocalTerminalAiSettingsNotifier.new,
          ),
          localTerminalAiManagedModelProvider.overrideWith(
            _StaticLocalTerminalAiManagedModelController.new,
          ),
          localTerminalAiRuntimeInfoProvider.overrideWith(
            (ref) async => _runtimeInfoState,
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: TerminalAiAssistantSheet(
              promptContext: const LocalTerminalAiPromptContext(
                hostLabel: 'prod',
                currentTerminalLine: 'git status',
              ),
              onInsertSuggestedCommand: (_) async {},
              onInsertCompletion: (_) async {},
              onOpenSettings: () {},
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
  }

  testWidgets(
    'keeps assistant actions enabled when the managed model is installed',
    (tester) async {
      _settingsState = const LocalTerminalAiSettings(enabled: true);
      _managedModelState = const LocalTerminalAiManagedModelState(
        status: LocalTerminalAiManagedModelStatus.installed,
        spec: _managedSpec,
        progress: 100,
      );

      await pumpAssistantSheet(tester);

      final suggestCommandsButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Suggest commands'),
      );
      final suggestCompletionButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Suggest completion'),
      );

      expect(suggestCommandsButton.onPressed, isNotNull);
      expect(suggestCompletionButton.onPressed, isNotNull);
      expect(find.text('Assistant available'), findsOneWidget);
    },
    variant: const TargetPlatformVariant(<TargetPlatform>{
      TargetPlatform.macOS,
    }),
  );

  testWidgets(
    'keeps assistant actions enabled when the Android managed model is installed',
    (tester) async {
      _settingsState = const LocalTerminalAiSettings(enabled: true);
      _managedModelState = const LocalTerminalAiManagedModelState(
        status: LocalTerminalAiManagedModelStatus.installed,
        spec: _managedSpec,
        progress: 100,
      );
      _runtimeInfoState = const LocalTerminalAiRuntimeInfo(
        provider: LocalTerminalAiPlatformProvider.androidAiCore,
        supportedPlatform: true,
        available: false,
        statusMessage:
            'Gemini Nano is supported here but still downloading or preparing.',
      );

      await pumpAssistantSheet(tester);

      final suggestCommandsButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Suggest commands'),
      );
      final suggestCompletionButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Suggest completion'),
      );

      expect(suggestCommandsButton.onPressed, isNotNull);
      expect(suggestCompletionButton.onPressed, isNotNull);
      expect(find.text('Assistant available'), findsOneWidget);
    },
    variant: const TargetPlatformVariant(<TargetPlatform>{
      TargetPlatform.android,
    }),
  );

  testWidgets(
    'disables assistant actions while the model is downloading',
    (tester) async {
      _settingsState = const LocalTerminalAiSettings(enabled: true);
      _managedModelState = const LocalTerminalAiManagedModelState(
        status: LocalTerminalAiManagedModelStatus.downloading,
        spec: _managedSpec,
        progress: 42,
      );

      await pumpAssistantSheet(tester);

      final suggestCommandsButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Suggest commands'),
      );
      final suggestCompletionButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Suggest completion'),
      );

      expect(suggestCommandsButton.onPressed, isNull);
      expect(suggestCompletionButton.onPressed, isNull);
      expect(find.text('Setup required'), findsOneWidget);
    },
    variant: const TargetPlatformVariant(<TargetPlatform>{
      TargetPlatform.macOS,
    }),
  );
}
