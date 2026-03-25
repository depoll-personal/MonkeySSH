import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The native on-device AI provider exposed by the current platform.
enum LocalTerminalAiPlatformProvider {
  /// No platform-native runtime is exposed for the current platform.
  none,

  /// Apple Foundation Models backed by Apple Intelligence.
  appleFoundationModels,

  /// Android AICore / Gemini Nano via ML Kit GenAI Prompt.
  androidAiCore,
}

/// Human-readable label for a [LocalTerminalAiPlatformProvider].
String localTerminalAiPlatformProviderLabel(
  LocalTerminalAiPlatformProvider provider,
) => switch (provider) {
  LocalTerminalAiPlatformProvider.none => 'No built-in model',
  LocalTerminalAiPlatformProvider.appleFoundationModels =>
    'Apple Foundation Models',
  LocalTerminalAiPlatformProvider.androidAiCore => 'Android AI Core',
};

/// Exception raised when the platform-native runtime fails to execute.
class LocalTerminalAiPlatformException implements Exception {
  /// Creates a new [LocalTerminalAiPlatformException].
  const LocalTerminalAiPlatformException(this.message);

  /// Human-readable error message.
  final String message;

  @override
  String toString() => message;
}

/// Runtime availability details for the native on-device AI provider.
class LocalTerminalAiRuntimeInfo {
  /// Creates a new [LocalTerminalAiRuntimeInfo].
  const LocalTerminalAiRuntimeInfo({
    required this.provider,
    required this.supportedPlatform,
    required this.available,
    required this.statusMessage,
    this.modelName,
  });

  /// A default unsupported runtime info object.
  const LocalTerminalAiRuntimeInfo.unsupported({
    this.provider = LocalTerminalAiPlatformProvider.none,
    this.statusMessage =
        'This platform does not expose a built-in on-device language model.',
  }) : supportedPlatform = false,
       available = false,
       modelName = null;

  /// Parses runtime info from a native method-channel result.
  factory LocalTerminalAiRuntimeInfo.fromMap(Map<Object?, Object?>? raw) {
    if (raw == null) {
      return const LocalTerminalAiRuntimeInfo.unsupported();
    }

    final statusMessage = (raw['statusMessage'] as String?)?.trim();
    return LocalTerminalAiRuntimeInfo(
      provider: switch ((raw['provider'] as String?)?.trim()) {
        'appleFoundationModels' =>
          LocalTerminalAiPlatformProvider.appleFoundationModels,
        'androidAiCore' => LocalTerminalAiPlatformProvider.androidAiCore,
        _ => LocalTerminalAiPlatformProvider.none,
      },
      supportedPlatform: raw['supportedPlatform'] as bool? ?? false,
      available: raw['available'] as bool? ?? false,
      statusMessage: statusMessage?.isNotEmpty ?? false
          ? statusMessage!
          : 'Native runtime status unavailable.',
      modelName: (raw['modelName'] as String?)?.trim(),
    );
  }

  /// The platform-native provider associated with this runtime.
  final LocalTerminalAiPlatformProvider provider;

  /// Whether this platform can expose a native on-device runtime at all.
  final bool supportedPlatform;

  /// Whether the native runtime is ready for inference on this device now.
  final bool available;

  /// Human-readable runtime status or guidance.
  final String statusMessage;

  /// Optional concrete model name returned by the native provider.
  final String? modelName;

  /// Whether the native runtime can be used for inference immediately.
  bool get canUseNativeRuntime => supportedPlatform && available;

  /// Human-readable provider label.
  String get providerLabel => localTerminalAiPlatformProviderLabel(provider);
}

/// Provider for the platform-native on-device AI bridge.
final localTerminalAiPlatformServiceProvider =
    Provider<LocalTerminalAiPlatformService>(
      (ref) => const LocalTerminalAiPlatformService(),
    );

/// Provider for the current native runtime availability state.
final localTerminalAiRuntimeInfoProvider =
    FutureProvider<LocalTerminalAiRuntimeInfo>(
      (ref) =>
          ref.watch(localTerminalAiPlatformServiceProvider).getRuntimeInfo(),
    );

/// Method-channel bridge to platform-native on-device AI runtimes.
class LocalTerminalAiPlatformService {
  /// Creates a new [LocalTerminalAiPlatformService].
  const LocalTerminalAiPlatformService();

  static const _channel = MethodChannel(
    'xyz.depollsoft.monkeyssh/local_terminal_ai',
  );

  static bool get _supportsPlatform =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS || Platform.isMacOS);

  /// Returns availability details for the current native on-device runtime.
  Future<LocalTerminalAiRuntimeInfo> getRuntimeInfo() async {
    if (!_supportsPlatform) {
      return const LocalTerminalAiRuntimeInfo.unsupported();
    }

    try {
      final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
        'getRuntimeInfo',
      );
      return LocalTerminalAiRuntimeInfo.fromMap(raw);
    } on PlatformException catch (error) {
      return LocalTerminalAiRuntimeInfo.unsupported(
        statusMessage: error.message ?? error.code,
      );
    } on MissingPluginException {
      return const LocalTerminalAiRuntimeInfo.unsupported(
        statusMessage: 'Native runtime bridge is not available in this build.',
      );
    }
  }

  /// Runs a prompt through the native on-device runtime and returns plain text.
  Future<String> generateText({
    required String prompt,
    required int maxTokens,
  }) async {
    if (!_supportsPlatform) {
      throw const LocalTerminalAiPlatformException(
        'This platform does not expose a built-in on-device language model.',
      );
    }

    try {
      final response = await _channel.invokeMethod<String>('generateText', {
        'prompt': prompt,
        'maxTokens': maxTokens,
      });
      final trimmedResponse = response?.trimRight();
      if (trimmedResponse == null || trimmedResponse.isEmpty) {
        throw const LocalTerminalAiPlatformException(
          'The native on-device model returned an empty response.',
        );
      }
      return trimmedResponse;
    } on PlatformException catch (error) {
      throw LocalTerminalAiPlatformException(error.message ?? error.code);
    } on MissingPluginException {
      throw const LocalTerminalAiPlatformException(
        'Native runtime bridge is not available in this build.',
      );
    }
  }
}
