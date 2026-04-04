import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'local_terminal_ai_platform_service.dart';
import 'local_terminal_ai_settings_service.dart';

const _gemma4E2BLiteRtLmUrl =
    'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm';
const _gemma4E2BModelId = 'gemma-4-E2B-it';
const _managedGemmaSessionTemperature = 0.2;

/// Download lifecycle for the managed Gemma 4 fallback.
enum LocalTerminalAiManagedModelStatus {
  /// No managed download is active for the current settings.
  idle,

  /// The managed model is currently downloading or installing.
  downloading,

  /// The managed model download finished and the runtime is being warmed up.
  verifying,

  /// The managed model is installed and ready to use.
  ready,

  /// The managed model failed to download or install.
  failed,
}

/// Platform-specific managed Gemma 4 artifact metadata.
class LocalTerminalAiManagedModelSpec {
  /// Creates a new [LocalTerminalAiManagedModelSpec].
  const LocalTerminalAiManagedModelSpec({
    required this.modelId,
    required this.displayName,
    required this.url,
    required this.fileType,
    required this.fileName,
    this.preferredBackend,
    this.foregroundDownload,
  });

  /// Stable model identifier used by `flutter_gemma`.
  final String modelId;

  /// Human-readable model name.
  final String displayName;

  /// Download URL for the managed model artifact.
  final String url;

  /// Model file type understood by `flutter_gemma`.
  final ModelFileType fileType;

  /// Artifact file name.
  final String fileName;

  /// Preferred inference backend for this managed model, if needed.
  final PreferredBackend? preferredBackend;

  /// Whether Android should force foreground download mode.
  final bool? foregroundDownload;

  /// Stable runtime signature for this managed model.
  String get signature =>
      '$modelId:${fileType.name}:$fileName:${preferredBackend?.name ?? 'default'}';
}

/// Current state of the managed Gemma 4 fallback download.
class LocalTerminalAiManagedModelState {
  /// Creates a new [LocalTerminalAiManagedModelState].
  const LocalTerminalAiManagedModelState({
    required this.status,
    this.spec,
    this.progress = 0,
    this.errorMessage,
  });

  /// Idle state with no active managed download.
  const LocalTerminalAiManagedModelState.idle()
    : this(status: LocalTerminalAiManagedModelStatus.idle);

  /// Current download/install status.
  final LocalTerminalAiManagedModelStatus status;

  /// The managed model currently being tracked, if any.
  final LocalTerminalAiManagedModelSpec? spec;

  /// Download progress percentage.
  final int progress;

  /// Human-readable failure message when [status] is failed.
  final String? errorMessage;

  /// Whether the managed fallback is ready to use.
  bool get isReady => status == LocalTerminalAiManagedModelStatus.ready;

  /// Whether a managed download is currently in flight.
  bool get isDownloading =>
      status == LocalTerminalAiManagedModelStatus.downloading;

  /// Whether a managed verification step is currently in flight.
  bool get isVerifying => status == LocalTerminalAiManagedModelStatus.verifying;

  /// Returns a copy of this state with replacements applied.
  LocalTerminalAiManagedModelState copyWith({
    LocalTerminalAiManagedModelStatus? status,
    LocalTerminalAiManagedModelSpec? spec,
    int? progress,
    String? errorMessage,
    bool clearErrorMessage = false,
  }) => LocalTerminalAiManagedModelState(
    status: status ?? this.status,
    spec: spec ?? this.spec,
    progress: progress ?? this.progress,
    errorMessage: clearErrorMessage ? null : errorMessage ?? this.errorMessage,
  );
}

/// Shared coordinator for the managed Gemma 4 fallback download.
abstract class LocalTerminalAiManagedModelCoordinator {
  /// Starts or cancels background synchronization for the current settings.
  Future<void> sync(
    LocalTerminalAiSettings settings, {
    LocalTerminalAiRuntimeInfo? runtimeInfo,
  });

  /// Ensures the managed fallback is ready and returns its spec when applicable.
  Future<LocalTerminalAiManagedModelSpec?> ensureReadyFor(
    LocalTerminalAiSettings settings,
  );

  /// Retries the current managed download if it is applicable.
  Future<void> retry(LocalTerminalAiSettings settings);
}

/// Provider for the managed Gemma 4 fallback state.
final localTerminalAiManagedModelProvider =
    NotifierProvider<
      LocalTerminalAiManagedModelController,
      LocalTerminalAiManagedModelState
    >(LocalTerminalAiManagedModelController.new);

/// Creates a managed Gemma inference session with conservative cross-platform
/// sampler settings.
Future<InferenceModelSession> createManagedGemmaInferenceSession(
  InferenceModel model,
) => model.createSession(temperature: _managedGemmaSessionTemperature);

/// Coordinates managed Gemma 4 fallback downloads through `flutter_gemma`.
class LocalTerminalAiManagedModelController
    extends Notifier<LocalTerminalAiManagedModelState>
    implements LocalTerminalAiManagedModelCoordinator {
  CancelToken? _cancelToken;
  Future<void>? _downloadFuture;
  String? _activeSignature;
  bool _disposed = false;

  @override
  LocalTerminalAiManagedModelState build() {
    ref.onDispose(() {
      _disposed = true;
      _cancelActiveDownload();
    });
    return const LocalTerminalAiManagedModelState.idle();
  }

  @override
  Future<void> sync(
    LocalTerminalAiSettings settings, {
    LocalTerminalAiRuntimeInfo? runtimeInfo,
  }) async {
    final spec = localTerminalAiManagedGemma4SpecForSettings(settings);
    if (spec == null) {
      _activeSignature = null;
      _cancelActiveDownload();
      if (!_disposed) {
        state = const LocalTerminalAiManagedModelState.idle();
      }
      return;
    }

    if (!shouldAutoSyncManagedGemma4(
      settings: settings,
      runtimeInfo: runtimeInfo,
    )) {
      _cancelActiveDownload();
      if (!_disposed && !state.isReady) {
        state = const LocalTerminalAiManagedModelState.idle();
      }
      return;
    }

    if (state.isReady && state.spec?.signature == spec.signature) {
      return;
    }

    unawaited(ensureReadyFor(settings));
  }

  @override
  Future<LocalTerminalAiManagedModelSpec?> ensureReadyFor(
    LocalTerminalAiSettings settings,
  ) async {
    final spec = localTerminalAiManagedGemma4SpecForSettings(settings);
    if (spec == null) {
      return null;
    }

    if (state.isReady && state.spec?.signature == spec.signature) {
      return state.spec;
    }

    if (_downloadFuture != null && _activeSignature == spec.signature) {
      await _downloadFuture;
      return _resolveCompletedSpec(spec);
    }

    _cancelActiveDownload();
    _activeSignature = spec.signature;
    final future = _downloadManagedModel(spec);
    _downloadFuture = future;
    try {
      await future;
    } finally {
      if (identical(_downloadFuture, future)) {
        _downloadFuture = null;
      }
    }
    return _resolveCompletedSpec(spec);
  }

  @override
  Future<void> retry(LocalTerminalAiSettings settings) async {
    if (localTerminalAiManagedGemma4SpecForSettings(settings) == null) {
      return;
    }
    _activeSignature = null;
    await ensureReadyFor(settings);
  }

  Future<LocalTerminalAiManagedModelSpec?> _resolveCompletedSpec(
    LocalTerminalAiManagedModelSpec spec,
  ) async {
    if (_disposed) {
      return null;
    }
    if (state.isReady && state.spec?.signature == spec.signature) {
      return state.spec;
    }
    if (state.status == LocalTerminalAiManagedModelStatus.failed &&
        state.spec?.signature == spec.signature) {
      throw Exception(
        state.errorMessage ??
            'Downloading the managed ${spec.displayName} fallback failed.',
      );
    }
    return null;
  }

  Future<void> _downloadManagedModel(
    LocalTerminalAiManagedModelSpec spec,
  ) async {
    final token = CancelToken();
    _cancelToken = token;
    if (!_disposed) {
      state = LocalTerminalAiManagedModelState(
        status: LocalTerminalAiManagedModelStatus.downloading,
        spec: spec,
      );
    }

    try {
      await _prepareManagedDownloadEnvironment();
      await FlutterGemma.initialize();
      final builder = FlutterGemma.installModel(
        modelType: ModelType.gemmaIt,
        fileType: spec.fileType,
      ).fromNetwork(spec.url, foreground: spec.foregroundDownload);
      await builder.withCancelToken(token).withProgress((progress) {
        if (_disposed || _activeSignature != spec.signature) {
          return;
        }
        state = state.copyWith(
          status: LocalTerminalAiManagedModelStatus.downloading,
          spec: spec,
          progress: progress,
          clearErrorMessage: true,
        );
      }).install();
      if (_disposed || _activeSignature != spec.signature) {
        return;
      }
      state = LocalTerminalAiManagedModelState(
        status: LocalTerminalAiManagedModelStatus.verifying,
        spec: spec,
        progress: 100,
      );
      await _verifyManagedModelRuntime(spec);
      if (_disposed || _activeSignature != spec.signature) {
        return;
      }
      state = LocalTerminalAiManagedModelState(
        status: LocalTerminalAiManagedModelStatus.ready,
        spec: spec,
        progress: 100,
      );
    } on Object catch (error) {
      if (CancelToken.isCancel(error)) {
        if (!_disposed && _activeSignature == spec.signature) {
          state = const LocalTerminalAiManagedModelState.idle();
        }
        return;
      }
      if (_disposed || _activeSignature != spec.signature) {
        return;
      }
      state = LocalTerminalAiManagedModelState(
        status: LocalTerminalAiManagedModelStatus.failed,
        spec: spec,
        errorMessage: _formatManagedModelSetupError(error, spec),
      );
    } finally {
      if (identical(_cancelToken, token)) {
        _cancelToken = null;
      }
    }
  }

  void _cancelActiveDownload() {
    final token = _cancelToken;
    if (token != null && !token.isCancelled) {
      token.cancel(
        'Managed Gemma 4 download is no longer needed for the current settings.',
      );
    }
    _cancelToken = null;
  }

  Future<void> _verifyManagedModelRuntime(
    LocalTerminalAiManagedModelSpec spec,
  ) async {
    final model = await FlutterGemma.getActiveModel(
      maxTokens: 256,
      preferredBackend: spec.preferredBackend,
    );
    try {
      final session = await createManagedGemmaInferenceSession(model);
      await session.close();
    } finally {
      await model.close();
    }
  }

  String _formatManagedModelSetupError(
    Object error,
    LocalTerminalAiManagedModelSpec spec,
  ) {
    final errorMessage = error.toString().trim();
    if (errorMessage.contains('Failed to invoke the compiled model') ||
        errorMessage.contains('failedToInitializeEngine') ||
        errorMessage.contains('Error building tflite model')) {
      return 'Managed ${spec.displayName} downloaded but could not start on this device. Retry the setup from Settings.';
    }
    return 'Managed ${spec.displayName} setup failed: $errorMessage';
  }

  Future<void> _prepareManagedDownloadEnvironment() async {
    if (kIsWeb || !Platform.isMacOS) {
      return;
    }

    final documentsDirectory = await getApplicationDocumentsDirectory();
    await documentsDirectory.create(recursive: true);

    final cacheDirectory = await getApplicationCacheDirectory();
    await cacheDirectory.create(recursive: true);
  }
}

/// Whether the current settings should use the managed Gemma 4 fallback.
bool shouldUseManagedGemma4Fallback(LocalTerminalAiSettings settings) =>
    localTerminalAiManagedGemma4SpecForSettings(settings) != null;

/// Whether managed Gemma 4 should start downloading in the background now.
bool shouldAutoSyncManagedGemma4({
  required LocalTerminalAiSettings settings,
  LocalTerminalAiRuntimeInfo? runtimeInfo,
}) => localTerminalAiManagedGemma4SpecForSettings(settings) != null;

/// Returns the managed Gemma 4 artifact for the current platform and settings.
LocalTerminalAiManagedModelSpec? localTerminalAiManagedGemma4SpecForSettings(
  LocalTerminalAiSettings settings,
) {
  if (!settings.enabled) {
    return null;
  }

  return localTerminalAiManagedGemma4Spec();
}

/// Returns the managed Gemma 4 artifact for the current platform, if supported.
LocalTerminalAiManagedModelSpec? localTerminalAiManagedGemma4Spec() {
  if (kIsWeb) {
    return null;
  }

  return switch (defaultTargetPlatform) {
    TargetPlatform.android => const LocalTerminalAiManagedModelSpec(
      modelId: _gemma4E2BModelId,
      displayName: 'Gemma 4 E2B',
      url: _gemma4E2BLiteRtLmUrl,
      fileType: ModelFileType.task,
      fileName: 'gemma-4-E2B-it.litertlm',
      foregroundDownload: true,
    ),
    TargetPlatform.iOS => const LocalTerminalAiManagedModelSpec(
      modelId: _gemma4E2BModelId,
      displayName: 'Gemma 4 E2B',
      url: _gemma4E2BLiteRtLmUrl,
      fileType: ModelFileType.task,
      fileName: 'gemma-4-E2B-it.litertlm',
    ),
    TargetPlatform.macOS ||
    TargetPlatform.windows ||
    TargetPlatform.linux => const LocalTerminalAiManagedModelSpec(
      modelId: _gemma4E2BModelId,
      displayName: 'Gemma 4 E2B',
      url: _gemma4E2BLiteRtLmUrl,
      fileType: ModelFileType.task,
      fileName: 'gemma-4-E2B-it.litertlm',
    ),
    TargetPlatform.fuchsia => null,
  };
}
