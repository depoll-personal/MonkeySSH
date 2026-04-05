import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'local_terminal_ai_credentials_service.dart';
import 'local_terminal_ai_platform_service.dart';
import 'local_terminal_ai_settings_service.dart';

const _gemma3nE2BTaskCommitHash = '66c93e118deff9961db659f241678e61b847d165';
const _gemma3nE2BTaskFileName = 'gemma-3n-E2B-it-int4.task';
const _gemma3nE2BTaskUrl =
    'https://huggingface.co/google/gemma-3n-E2B-it-litert-preview/resolve/'
    '$_gemma3nE2BTaskCommitHash/$_gemma3nE2BTaskFileName?download=true';
const _gemma3nE2BModelId = 'gemma-3n-E2B-it';
const _gemma4E2BLiteRtLmCommitHash = '616f4124e6ff216292f16e7f73ff33b5ba9a4dd4';
const _gemma4E2BLiteRtLmFileName = 'gemma-4-E2B-it.litertlm';
const _gemma4E2BLiteRtLmUrl =
    'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/'
    '$_gemma4E2BLiteRtLmCommitHash/$_gemma4E2BLiteRtLmFileName?download=true';
const _gemma4E2BModelId = 'gemma-4-E2B-it';
const _managedGemmaSessionTemperature = 0.2;

/// The context window size used when initializing the managed Gemma model.
///
/// This value is passed to `FlutterGemma.getActiveModel(maxTokens:)` both
/// during verification warmup and during inference. It must be consistent
/// because `flutter_gemma` caches the native model singleton by model name
/// only — a warmup at 256 followed by inference at 1024 would silently
/// reuse the 256-token engine, causing prompt-too-long failures.
const managedGemmaMaxTokens = 4096;

/// Download lifecycle for the managed terminal AI model fallback.
enum LocalTerminalAiManagedModelStatus {
  /// No managed download is active for the current settings.
  idle,

  /// The managed model is currently downloading or installing.
  downloading,

  /// The managed model is downloaded and installed, but not yet warmed up.
  installed,

  /// The managed model download finished and the runtime is being warmed up.
  verifying,

  /// The managed model is installed and ready to use.
  ready,

  /// The managed model failed to download or install.
  failed,
}

/// Platform-specific managed terminal AI artifact metadata.
class LocalTerminalAiManagedModelSpec {
  /// Creates a new [LocalTerminalAiManagedModelSpec].
  const LocalTerminalAiManagedModelSpec({
    required this.modelId,
    required this.displayName,
    required this.url,
    required this.fileType,
    required this.fileName,
    this.requiresHuggingFaceToken = false,
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

  /// Whether the download requires a Hugging Face token.
  final bool requiresHuggingFaceToken;

  /// Preferred inference backend for this managed model, if needed.
  final PreferredBackend? preferredBackend;

  /// Whether Android should force foreground download mode.
  final bool? foregroundDownload;

  /// Stable runtime signature for this managed model.
  String get signature =>
      '$modelId:${fileType.name}:$fileName:${preferredBackend?.name ?? 'default'}';
}

/// Current state of the managed terminal AI fallback download.
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

  /// Whether the managed fallback is downloaded and installed.
  bool get isInstalled =>
      status == LocalTerminalAiManagedModelStatus.installed || isReady;

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

/// Shared coordinator for the managed terminal AI fallback download.
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

/// Provider for the managed terminal AI fallback state.
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

/// Whether an error indicates that Gemma started downloading but could not
/// initialize a runnable inference engine on the device.
bool isManagedGemmaRuntimeStartupError(Object error) {
  final errorMessage = error.toString().trim();
  return errorMessage.contains('Failed to invoke the compiled model') ||
      errorMessage.contains('failedToInitializeEngine') ||
      errorMessage.contains('Error building tflite model');
}

/// Returns the backend order to try for managed Gemma runtime startup.
List<PreferredBackend?> managedGemmaRuntimeBackends(
  LocalTerminalAiManagedModelSpec spec,
) {
  final preferredBackend = spec.preferredBackend;
  if (preferredBackend == null || preferredBackend == PreferredBackend.cpu) {
    return <PreferredBackend?>[preferredBackend];
  }
  return <PreferredBackend?>[preferredBackend, PreferredBackend.cpu];
}

/// Runs a managed Gemma operation, retrying CPU after a startup failure when
/// the preferred backend is more aggressive than CPU.
Future<T> runWithManagedGemmaBackendFallback<T>({
  required LocalTerminalAiManagedModelSpec spec,
  required Future<T> Function(PreferredBackend? preferredBackend) operation,
}) async {
  final backends = managedGemmaRuntimeBackends(spec);
  Object? lastError;
  StackTrace? lastStackTrace;
  for (var index = 0; index < backends.length; index += 1) {
    final backend = backends[index];
    try {
      return await operation(backend);
    } on Exception catch (error, stackTrace) {
      lastError = error;
      lastStackTrace = stackTrace;
      final hasFallback = index + 1 < backends.length;
      if (!hasFallback || !isManagedGemmaRuntimeStartupError(error)) {
        rethrow;
      }
    }
  }

  if (lastError case final Object error) {
    Error.throwWithStackTrace(error, lastStackTrace!);
  }
  throw StateError('Managed Gemma backend fallback exhausted without running.');
}

/// Coordinates managed terminal AI model downloads through `flutter_gemma`.
class LocalTerminalAiManagedModelController
    extends Notifier<LocalTerminalAiManagedModelState>
    implements LocalTerminalAiManagedModelCoordinator {
  late LocalTerminalAiCredentialsService _credentials;
  CancelToken? _cancelToken;
  Future<void>? _downloadFuture;
  Future<void>? _verificationFuture;
  String? _activeSignature;
  bool _disposed = false;

  @override
  LocalTerminalAiManagedModelState build() {
    _credentials = ref.watch(localTerminalAiCredentialsServiceProvider);
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
    final spec = localTerminalAiManagedModelSpecForSettings(settings);
    if (spec == null) {
      _activeSignature = null;
      _cancelActiveDownload();
      if (!_disposed) {
        state = const LocalTerminalAiManagedModelState.idle();
      }
      return;
    }

    if (!shouldAutoSyncManagedLocalTerminalAiModel(
      settings: settings,
      runtimeInfo: runtimeInfo,
    )) {
      _cancelActiveDownload();
      if (!_disposed && !state.isReady) {
        state = const LocalTerminalAiManagedModelState.idle();
      }
      return;
    }

    final autoVerify = shouldAutoVerifyManagedLocalTerminalAiModelInBackground(
      settings: settings,
      runtimeInfo: runtimeInfo,
    );
    if (state.spec?.signature == spec.signature &&
        (state.isDownloading ||
            state.isVerifying ||
            (autoVerify ? state.isReady : state.isInstalled))) {
      return;
    }

    unawaited(_syncManagedModel(spec: spec, verifyRuntime: autoVerify));
  }

  @override
  Future<LocalTerminalAiManagedModelSpec?> ensureReadyFor(
    LocalTerminalAiSettings settings,
  ) async {
    final spec = localTerminalAiManagedModelSpecForSettings(settings);
    if (spec == null) {
      return null;
    }

    if (state.isReady && state.spec?.signature == spec.signature) {
      return state.spec;
    }

    await _ensureManagedModelDownloaded(spec);
    await _ensureManagedModelVerified(spec);
    return _resolveCompletedSpec(spec);
  }

  @override
  Future<void> retry(LocalTerminalAiSettings settings) async {
    if (localTerminalAiManagedModelSpecForSettings(settings) == null) {
      return;
    }
    _cancelActiveDownload();
    _verificationFuture = null;
    _activeSignature = null;
    await ensureReadyFor(settings);
  }

  Future<void> _syncManagedModel({
    required LocalTerminalAiManagedModelSpec spec,
    required bool verifyRuntime,
  }) async {
    await _ensureManagedModelDownloaded(spec);
    if (verifyRuntime) {
      await _ensureManagedModelVerified(spec);
    }
  }

  Future<void> _ensureManagedModelDownloaded(
    LocalTerminalAiManagedModelSpec spec,
  ) async {
    if (state.isInstalled && state.spec?.signature == spec.signature) {
      return;
    }

    if (_downloadFuture != null && _activeSignature == spec.signature) {
      await _downloadFuture;
      _throwIfManagedModelFailed(spec);
      return;
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
    _throwIfManagedModelFailed(spec);
  }

  Future<void> _ensureManagedModelVerified(
    LocalTerminalAiManagedModelSpec spec,
  ) async {
    if (state.isReady && state.spec?.signature == spec.signature) {
      return;
    }

    if (_verificationFuture != null && _activeSignature == spec.signature) {
      await _verificationFuture;
      _throwIfManagedModelFailed(spec);
      return;
    }

    await _ensureManagedModelDownloaded(spec);
    if (_disposed || _activeSignature != spec.signature) {
      return;
    }

    final future = _verifyInstalledManagedModel(spec);
    _verificationFuture = future;
    try {
      await future;
    } finally {
      if (identical(_verificationFuture, future)) {
        _verificationFuture = null;
      }
    }
    _throwIfManagedModelFailed(spec);
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
      final huggingFaceToken = await _credentials.getHuggingFaceToken();
      if (spec.requiresHuggingFaceToken && huggingFaceToken == null) {
        throw Exception(
          'Add a Hugging Face token in Settings to download ${spec.displayName}.',
        );
      }
      final builder =
          FlutterGemma.installModel(
            modelType: ModelType.gemmaIt,
            fileType: spec.fileType,
          ).fromNetwork(
            spec.url,
            token: huggingFaceToken,
            foreground: spec.foregroundDownload,
          );
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
        status: LocalTerminalAiManagedModelStatus.installed,
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

  Future<void> _verifyInstalledManagedModel(
    LocalTerminalAiManagedModelSpec spec,
  ) async {
    if (!_disposed) {
      state = LocalTerminalAiManagedModelState(
        status: LocalTerminalAiManagedModelStatus.verifying,
        spec: spec,
        progress: 100,
      );
    }

    try {
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
      if (_disposed || _activeSignature != spec.signature) {
        return;
      }
      state = LocalTerminalAiManagedModelState(
        status: LocalTerminalAiManagedModelStatus.failed,
        spec: spec,
        progress: 100,
        errorMessage: _formatManagedModelSetupError(error, spec),
      );
    }
  }

  void _cancelActiveDownload() {
    final token = _cancelToken;
    if (token != null && !token.isCancelled) {
      token.cancel(
        'Managed terminal AI download is no longer needed for the current settings.',
      );
    }
    _cancelToken = null;
  }

  Future<void> _verifyManagedModelRuntime(
    LocalTerminalAiManagedModelSpec spec,
  ) => runWithManagedGemmaBackendFallback(
    spec: spec,
    operation: (preferredBackend) async {
      final model = await FlutterGemma.getActiveModel(
        // ignore: avoid_redundant_argument_values
        maxTokens: managedGemmaMaxTokens,
        preferredBackend: preferredBackend,
      );
      // Create and immediately close a throwaway session to force the native
      // engine to finish initialization (weight upload, GPU compilation, etc.).
      // We intentionally do NOT close the model itself so it stays warm as a
      // singleton — the next getActiveModel() call reuses this engine without
      // a cold-start penalty.
      final session = await createManagedGemmaInferenceSession(model);
      await session.close();
    },
  );

  String _formatManagedModelSetupError(
    Object error,
    LocalTerminalAiManagedModelSpec spec,
  ) {
    final errorMessage = error.toString().trim();
    const exceptionPrefix = 'Exception: ';
    if (errorMessage.startsWith(
      '$exceptionPrefix'
      'Add a Hugging Face token in Settings',
    )) {
      return errorMessage.substring(exceptionPrefix.length);
    }
    if (isManagedGemmaRuntimeStartupError(error)) {
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

  void _throwIfManagedModelFailed(LocalTerminalAiManagedModelSpec spec) {
    if (state.status == LocalTerminalAiManagedModelStatus.failed &&
        state.spec?.signature == spec.signature) {
      throw Exception(
        state.errorMessage ??
            'Downloading the managed ${spec.displayName} fallback failed.',
      );
    }
  }
}

/// Whether the current settings should use a managed terminal AI model.
bool shouldUseManagedLocalTerminalAiModel(LocalTerminalAiSettings settings) =>
    localTerminalAiManagedModelSpecForSettings(settings) != null;

/// Whether the managed terminal AI model should start downloading now.
bool shouldAutoSyncManagedLocalTerminalAiModel({
  required LocalTerminalAiSettings settings,
  LocalTerminalAiRuntimeInfo? runtimeInfo,
}) => localTerminalAiManagedModelSpecForSettings(settings) != null;

/// Whether the managed terminal AI model should be warmed up in background.
bool shouldAutoVerifyManagedLocalTerminalAiModelInBackground({
  required LocalTerminalAiSettings settings,
  LocalTerminalAiRuntimeInfo? runtimeInfo,
}) {
  if (localTerminalAiManagedModelSpecForSettings(settings) == null) {
    return false;
  }

  return true;
}

/// Returns the managed terminal AI model for the current platform and settings.
LocalTerminalAiManagedModelSpec? localTerminalAiManagedModelSpecForSettings(
  LocalTerminalAiSettings settings,
) {
  if (!settings.enabled) {
    return null;
  }

  return localTerminalAiManagedModelSpec();
}

/// Returns the managed terminal AI model for the current platform, if supported.
LocalTerminalAiManagedModelSpec? localTerminalAiManagedModelSpec() {
  if (kIsWeb) {
    return null;
  }

  return switch (defaultTargetPlatform) {
    TargetPlatform.android => const LocalTerminalAiManagedModelSpec(
      modelId: _gemma4E2BModelId,
      displayName: 'Gemma 4 E2B',
      url: _gemma4E2BLiteRtLmUrl,
      fileType: ModelFileType.litertlm,
      fileName: _gemma4E2BLiteRtLmFileName,
      preferredBackend: PreferredBackend.gpu,
      foregroundDownload: true,
    ),
    TargetPlatform.iOS => const LocalTerminalAiManagedModelSpec(
      modelId: _gemma3nE2BModelId,
      displayName: 'Gemma 3n E2B',
      url: _gemma3nE2BTaskUrl,
      fileType: ModelFileType.task,
      fileName: _gemma3nE2BTaskFileName,
      requiresHuggingFaceToken: true,
      preferredBackend: PreferredBackend.gpu,
    ),
    TargetPlatform.macOS ||
    TargetPlatform.windows ||
    TargetPlatform.linux => const LocalTerminalAiManagedModelSpec(
      modelId: _gemma4E2BModelId,
      displayName: 'Gemma 4 E2B',
      url: _gemma4E2BLiteRtLmUrl,
      fileType: ModelFileType.litertlm,
      fileName: _gemma4E2BLiteRtLmFileName,
    ),
    TargetPlatform.fuchsia => null,
  };
}
