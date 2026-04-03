import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;

import 'settings_service.dart';

/// Model families supported by the on-device terminal AI assistant.
const supportedLocalTerminalAiModelTypes = <ModelType>[
  ModelType.gemmaIt,
  ModelType.functionGemma,
  ModelType.qwen,
  ModelType.deepSeek,
  ModelType.general,
];

/// Human-readable label for a [ModelType] used by the terminal AI assistant.
String localTerminalAiModelTypeLabel(ModelType modelType) =>
    switch (modelType) {
      ModelType.gemmaIt => 'Gemma',
      ModelType.functionGemma => 'FunctionGemma',
      ModelType.qwen => 'Qwen',
      ModelType.deepSeek => 'DeepSeek',
      ModelType.general => 'General',
      ModelType.llama => 'Llama',
      ModelType.hammer => 'Hammer',
    };

/// Returns the supported fallback model file label for the current platform.
String localTerminalAiSupportedModelFileLabel() {
  if (kIsWeb) {
    return '`.task` or `.litertlm` file';
  }

  return switch (defaultTargetPlatform) {
    TargetPlatform.iOS => '`.task` file',
    TargetPlatform.android => '`.task` or `.litertlm` file',
    TargetPlatform.macOS ||
    TargetPlatform.windows ||
    TargetPlatform.linux => '`.litertlm` file',
    TargetPlatform.fuchsia => 'compatible model file',
  };
}

/// Returns setup guidance for fallback model files on the current platform.
String localTerminalAiSupportedModelFileHelpText() {
  if (kIsWeb) {
    return 'Use a web-compatible `.task` or `.litertlm` file. Commands are never run automatically.';
  }

  return switch (defaultTargetPlatform) {
    TargetPlatform.iOS =>
      'Use `.task` on iOS. Commands are never run automatically.',
    TargetPlatform.android =>
      'Use `.task` or `.litertlm` on Android. Commands are never run automatically.',
    TargetPlatform.macOS || TargetPlatform.windows || TargetPlatform.linux =>
      'Use `.litertlm` on macOS, Windows, or Linux. Commands are never run automatically.',
    TargetPlatform.fuchsia =>
      'Use a compatible local model file for this platform. Commands are never run automatically.',
  };
}

/// Persisted settings for the experimental on-device terminal AI assistant.
class LocalTerminalAiSettings {
  /// Creates a new [LocalTerminalAiSettings].
  const LocalTerminalAiSettings({
    required this.enabled,
    required this.modelType,
    required this.preferNativeRuntime,
    this.modelPath,
  });

  /// Whether the assistant is enabled.
  final bool enabled;

  /// The selected model family.
  final ModelType modelType;

  /// Whether the app should prefer a built-in native runtime when available.
  final bool preferNativeRuntime;

  /// The selected local model file path.
  final String? modelPath;

  /// Whether a model path has been selected.
  bool get hasModelPath => modelPath != null && modelPath!.trim().isNotEmpty;

  /// Whether the configured model file extension is supported.
  bool get hasSupportedModelFileType => inferredFileType != null;

  /// Whether the fallback assistant model can be used immediately.
  bool get isReady => enabled && hasConfiguredFallbackModel;

  /// Whether a fallback model file is fully configured.
  bool get hasConfiguredFallbackModel =>
      hasModelPath && hasSupportedModelFileType;

  /// The selected model file name, if any.
  String? get modelFileName =>
      modelPath == null ? null : path.basename(modelPath!);

  /// The file type inferred from the selected model path.
  ModelFileType? get inferredFileType {
    final currentPath = modelPath;
    if (currentPath == null || currentPath.trim().isEmpty) {
      return null;
    }

    return switch (path.extension(currentPath).toLowerCase()) {
      '.task' when _supportsTaskFallbackModels() => ModelFileType.task,
      '.litertlm' when _supportsLiteRtLmFallbackModels() => ModelFileType.task,
      _ => null,
    };
  }

  /// Stable signature describing the active assistant configuration.
  String get signature =>
      '${modelType.name}:${preferNativeRuntime ? 'native' : 'fallback'}:'
      '${modelPath ?? ''}:${inferredFileType?.name ?? ''}';

  /// Returns a copy of this settings object with replacements applied.
  LocalTerminalAiSettings copyWith({
    bool? enabled,
    ModelType? modelType,
    bool? preferNativeRuntime,
    String? modelPath,
    bool clearModelPath = false,
  }) => LocalTerminalAiSettings(
    enabled: enabled ?? this.enabled,
    modelType: modelType ?? this.modelType,
    preferNativeRuntime: preferNativeRuntime ?? this.preferNativeRuntime,
    modelPath: clearModelPath ? null : modelPath ?? this.modelPath,
  );
}

/// Provider for the terminal AI assistant settings.
final localTerminalAiSettingsProvider =
    NotifierProvider<LocalTerminalAiSettingsNotifier, LocalTerminalAiSettings>(
      LocalTerminalAiSettingsNotifier.new,
    );

/// Notifier for persisted terminal AI assistant settings.
class LocalTerminalAiSettingsNotifier
    extends Notifier<LocalTerminalAiSettings> {
  late final SettingsService _settings;
  bool _disposed = false;

  @override
  LocalTerminalAiSettings build() {
    _settings = ref.watch(settingsServiceProvider);
    _disposed = false;
    ref.onDispose(() => _disposed = true);
    unawaited(Future<void>.microtask(_init));
    return const LocalTerminalAiSettings(
      enabled: false,
      modelType: ModelType.gemmaIt,
      preferNativeRuntime: true,
    );
  }

  Future<void> _init() async {
    final enabled = await _settings.getBool(SettingKeys.localTerminalAiEnabled);
    final modelPath = await _settings.getString(
      SettingKeys.localTerminalAiModelPath,
    );
    final storedModelType = await _settings.getString(
      SettingKeys.localTerminalAiModelType,
    );
    final preferNativeRuntime = await _settings.getBool(
      SettingKeys.localTerminalAiPreferNativeRuntime,
      defaultValue: true,
    );
    if (_disposed) {
      return;
    }

    state = LocalTerminalAiSettings(
      enabled: enabled,
      modelType: _parseModelType(storedModelType),
      preferNativeRuntime: preferNativeRuntime,
      modelPath: modelPath,
    );
  }

  /// Enables or disables the assistant.
  Future<void> setEnabled({required bool enabled}) async {
    await _settings.setBool(SettingKeys.localTerminalAiEnabled, value: enabled);
    state = state.copyWith(enabled: enabled);
  }

  /// Updates the selected local model file path.
  Future<void> setModelPath(String? modelPath) async {
    final normalizedPath = modelPath?.trim();
    if (normalizedPath == null || normalizedPath.isEmpty) {
      await _settings.delete(SettingKeys.localTerminalAiModelPath);
      state = state.copyWith(clearModelPath: true);
      return;
    }

    await _settings.setString(
      SettingKeys.localTerminalAiModelPath,
      normalizedPath,
    );
    state = state.copyWith(modelPath: normalizedPath);
  }

  /// Updates the selected model family.
  Future<void> setModelType(ModelType modelType) async {
    await _settings.setString(
      SettingKeys.localTerminalAiModelType,
      modelType.name,
    );
    state = state.copyWith(modelType: modelType);
  }

  /// Updates whether the assistant should prefer a built-in native runtime.
  Future<void> setPreferNativeRuntime({
    required bool preferNativeRuntime,
  }) async {
    await _settings.setBool(
      SettingKeys.localTerminalAiPreferNativeRuntime,
      value: preferNativeRuntime,
    );
    state = state.copyWith(preferNativeRuntime: preferNativeRuntime);
  }

  ModelType _parseModelType(String? value) => switch (value) {
    'functionGemma' => ModelType.functionGemma,
    'qwen' => ModelType.qwen,
    'deepSeek' => ModelType.deepSeek,
    'general' => ModelType.general,
    'llama' => ModelType.llama,
    'hammer' => ModelType.hammer,
    _ => ModelType.gemmaIt,
  };
}

bool _supportsTaskFallbackModels() {
  if (kIsWeb) {
    return true;
  }

  return switch (defaultTargetPlatform) {
    TargetPlatform.iOS || TargetPlatform.android => true,
    TargetPlatform.macOS ||
    TargetPlatform.windows ||
    TargetPlatform.linux ||
    TargetPlatform.fuchsia => false,
  };
}

bool _supportsLiteRtLmFallbackModels() {
  if (kIsWeb) {
    return true;
  }

  return switch (defaultTargetPlatform) {
    TargetPlatform.android ||
    TargetPlatform.macOS ||
    TargetPlatform.windows ||
    TargetPlatform.linux => true,
    TargetPlatform.iOS || TargetPlatform.fuchsia => false,
  };
}
