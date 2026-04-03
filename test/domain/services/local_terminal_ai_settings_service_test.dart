import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monkeyssh/domain/services/local_terminal_ai_settings_service.dart';

void main() {
  test('desktop fallback validation requires litertlm files', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    const taskSettings = LocalTerminalAiSettings(
      enabled: true,
      modelType: ModelType.gemmaIt,
      preferNativeRuntime: false,
      modelPath: '/models/gemma.task',
    );
    const liteRtLmSettings = LocalTerminalAiSettings(
      enabled: true,
      modelType: ModelType.gemmaIt,
      preferNativeRuntime: false,
      modelPath: '/models/gemma.litertlm',
    );

    expect(taskSettings.hasConfiguredFallbackModel, isFalse);
    expect(liteRtLmSettings.hasConfiguredFallbackModel, isTrue);
  });

  test('labels the Gemma family broadly enough for newer variants', () {
    expect(localTerminalAiModelTypeLabel(ModelType.gemmaIt), 'Gemma');
  });
}
