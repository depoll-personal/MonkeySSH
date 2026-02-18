import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/ai_cli_provider.dart';
import 'ai_cli_command_builder.dart';
import 'ssh_service.dart';

/// Event types emitted by [AiRuntimeService].
enum AiRuntimeEventType {
  /// A runtime command was started.
  started,

  /// Runtime stdout chunk.
  stdout,

  /// Runtime stderr chunk.
  stderr,

  /// Runtime finished.
  completed,

  /// Runtime was cancelled.
  cancelled,

  /// Runtime retry was requested.
  retried,

  /// Runtime error occurred.
  error,
}

/// Launch parameters for an AI runtime command.
class AiRuntimeLaunchRequest {
  /// Creates an [AiRuntimeLaunchRequest].
  const AiRuntimeLaunchRequest({
    required this.aiSessionId,
    required this.connectionId,
    required this.provider,
    required this.remoteWorkingDirectory,
    this.executableOverride,
    this.structuredOutput = false,
    this.extraArguments = const <String>[],
  });

  /// AI session ID from the persistence layer.
  final int aiSessionId;

  /// Existing SSH connection ID to run on.
  final int connectionId;

  /// Provider executable metadata.
  final AiCliProvider provider;

  /// Remote working directory where the command starts.
  final String remoteWorkingDirectory;

  /// Optional shell command override used to launch provider executable.
  final String? executableOverride;

  /// Whether to request structured provider output.
  final bool structuredOutput;

  /// Extra CLI arguments appended to the provider command.
  final List<String> extraArguments;
}

/// Runtime event payload.
class AiRuntimeEvent {
  /// Creates an [AiRuntimeEvent].
  const AiRuntimeEvent({
    required this.type,
    required this.aiSessionId,
    required this.connectionId,
    required this.provider,
    this.chunk,
    this.exitCode,
    this.error,
    this.stackTrace,
  });

  /// Event type.
  final AiRuntimeEventType type;

  /// AI session ID associated with this event.
  final int aiSessionId;

  /// SSH connection ID associated with this event.
  final int connectionId;

  /// Provider associated with this event.
  final AiCliProvider provider;

  /// Incremental output content for stdout/stderr events.
  final String? chunk;

  /// Process exit code when available.
  final int? exitCode;

  /// Error object when [type] is [AiRuntimeEventType.error].
  final Object? error;

  /// Error stack trace when available.
  final StackTrace? stackTrace;
}

/// Exception thrown when runtime actions fail.
class AiRuntimeServiceException implements Exception {
  /// Creates an [AiRuntimeServiceException].
  const AiRuntimeServiceException(this.message, {this.cause, this.stackTrace});

  /// Human-readable error message.
  final String message;

  /// Underlying cause, if available.
  final Object? cause;

  /// Stack trace associated with [cause], if available.
  final StackTrace? stackTrace;

  @override
  String toString() => cause == null
      ? 'AiRuntimeServiceException: $message'
      : 'AiRuntimeServiceException: $message ($cause)';
}

/// Resolves a runtime shell from an active SSH connection.
abstract interface class AiRuntimeShellResolver {
  /// Returns a shell for [connectionId], or null when unavailable.
  AiRuntimeShell? resolve(int connectionId);
}

/// Shell abstraction used to launch provider commands.
abstract interface class AiRuntimeShell {
  /// Executes [command] on the remote host.
  Future<AiRuntimeProcess> execute(String command);
}

/// Running process abstraction for streaming and control.
abstract interface class AiRuntimeProcess {
  /// Incremental stdout stream.
  Stream<String> get stdout;

  /// Incremental stderr stream.
  Stream<String> get stderr;

  /// Completes when the remote process exits.
  Future<void> get done;

  /// Exit code when available.
  int? get exitCode;

  /// Sends incremental input to process stdin.
  void write(String input);

  /// Requests process termination.
  Future<void> terminate();

  /// Releases process resources.
  Future<void> close();
}

/// [AiRuntimeShellResolver] backed by [ActiveSessionsNotifier].
class ActiveSessionsAiRuntimeShellResolver implements AiRuntimeShellResolver {
  /// Creates an [ActiveSessionsAiRuntimeShellResolver].
  const ActiveSessionsAiRuntimeShellResolver(this._activeSessions);

  final ActiveSessionsNotifier _activeSessions;

  @override
  AiRuntimeShell? resolve(int connectionId) {
    final session = _activeSessions.getSession(connectionId);
    if (session == null) {
      return null;
    }
    return SshAiRuntimeShell(session);
  }
}

/// [AiRuntimeShell] adapter for [SshSession].
class SshAiRuntimeShell implements AiRuntimeShell {
  /// Creates an [SshAiRuntimeShell].
  const SshAiRuntimeShell(this._session);

  final SshSession _session;

  @override
  Future<AiRuntimeProcess> execute(String command) async {
    final sshSession = await _session.execute(command);
    return SshAiRuntimeProcess(sshSession);
  }
}

/// [AiRuntimeProcess] adapter for [SSHSession].
class SshAiRuntimeProcess implements AiRuntimeProcess {
  /// Creates an [SshAiRuntimeProcess].
  const SshAiRuntimeProcess(this._session);

  final SSHSession _session;

  @override
  Stream<String> get stdout =>
      _session.stdout.cast<List<int>>().transform(utf8.decoder);

  @override
  Stream<String> get stderr =>
      _session.stderr.cast<List<int>>().transform(utf8.decoder);

  @override
  Future<void> get done => _session.done;

  @override
  int? get exitCode => _session.exitCode;

  @override
  void write(String input) {
    _session.write(Uint8List.fromList(utf8.encode(input)));
  }

  @override
  Future<void> terminate() async {
    _session.kill(SSHSignal.TERM);
    await _session.stdin.close();
  }

  @override
  Future<void> close() async {
    _session.close();
  }
}

/// Domain service that runs AI CLIs over active SSH sessions.
class AiRuntimeService {
  /// Creates an [AiRuntimeService].
  AiRuntimeService({
    required AiRuntimeShellResolver shellResolver,
    AiCliCommandBuilder? commandBuilder,
  }) : _shellResolver = shellResolver,
       _commandBuilder = commandBuilder ?? const AiCliCommandBuilder();

  final AiRuntimeShellResolver _shellResolver;
  final AiCliCommandBuilder _commandBuilder;
  final StreamController<AiRuntimeEvent> _eventsController =
      StreamController<AiRuntimeEvent>.broadcast();

  final Map<int, AiRuntimeProcess> _activeProcesses = <int, AiRuntimeProcess>{};
  final Map<int, AiRuntimeLaunchRequest> _activeLaunchRequests =
      <int, AiRuntimeLaunchRequest>{};
  final Map<int, AiRuntimeLaunchRequest> _lastLaunchRequests =
      <int, AiRuntimeLaunchRequest>{};
  final Map<int, StreamSubscription<String>> _stdoutSubscriptions =
      <int, StreamSubscription<String>>{};
  final Map<int, StreamSubscription<String>> _stderrSubscriptions =
      <int, StreamSubscription<String>>{};
  final Set<int> _cancelRequestedSessionIds = <int>{};
  final Set<int> _launchingSessionIds = <int>{};
  bool _disposed = false;

  /// Runtime events stream.
  Stream<AiRuntimeEvent> get events => _eventsController.stream;

  /// Whether a provider command is currently active.
  bool get hasActiveRun =>
      _activeProcesses.isNotEmpty || _launchingSessionIds.isNotEmpty;

  /// Whether the provided [aiSessionId] currently has an active runtime.
  bool hasActiveRunForSession(int aiSessionId) =>
      _activeProcesses.containsKey(aiSessionId) ||
      _launchingSessionIds.contains(aiSessionId);

  /// Launches a provider command on an existing SSH connection.
  Future<void> launch(AiRuntimeLaunchRequest request) async {
    _ensureNotDisposed();
    final aiSessionId = request.aiSessionId;
    if (hasActiveRunForSession(aiSessionId)) {
      throw AiRuntimeServiceException(
        'A runtime command is already active for session $aiSessionId.',
      );
    }
    _launchingSessionIds.add(aiSessionId);

    try {
      final shell = _shellResolver.resolve(request.connectionId);
      if (shell == null) {
        throw AiRuntimeServiceException(
          'No active SSH session found for connection ${request.connectionId}.',
        );
      }

      final command = _commandBuilder.buildLaunchCommand(
        provider: request.provider,
        remoteWorkingDirectory: request.remoteWorkingDirectory,
        executableOverride: request.executableOverride,
        structuredOutput: request.structuredOutput,
        extraArguments: request.extraArguments,
      );

      final process = await shell.execute(command);
      if (_disposed) {
        await _cleanupDetachedProcess(process);
        throw const AiRuntimeServiceException(
          'AiRuntimeService was disposed during launch.',
        );
      }

      _activeProcesses[aiSessionId] = process;
      _activeLaunchRequests[aiSessionId] = request;
      _lastLaunchRequests[aiSessionId] = request;
      _cancelRequestedSessionIds.remove(aiSessionId);
      _attachOutputStreams(process, request);

      _emitEvent(
        AiRuntimeEvent(
          type: AiRuntimeEventType.started,
          aiSessionId: request.aiSessionId,
          connectionId: request.connectionId,
          provider: request.provider,
        ),
      );

      unawaited(_watchCompletion(aiSessionId, process));
    } on AiRuntimeServiceException {
      rethrow;
    } on Exception catch (exception, stackTrace) {
      throw AiRuntimeServiceException(
        'Failed to execute runtime command.',
        cause: exception,
        stackTrace: stackTrace,
      );
    } finally {
      _launchingSessionIds.remove(aiSessionId);
    }
  }

  /// Sends incremental stdin content to the active runtime command.
  Future<void> send(
    String input, {
    bool appendNewline = false,
    int? aiSessionId,
  }) async {
    _ensureNotDisposed();
    final sessionId = _resolveTargetSessionId(
      aiSessionId: aiSessionId,
      operation: 'send input',
    );
    final process = _activeProcesses[sessionId];
    final request = _activeLaunchRequests[sessionId];
    if (process == null || request == null) {
      throw AiRuntimeServiceException(
        'Cannot send input because no runtime command is active for session $sessionId.',
      );
    }

    final payload = appendNewline ? '$input\n' : input;
    try {
      process.write(payload);
    } on Exception catch (exception, stackTrace) {
      _emitErrorEvent(request, exception, stackTrace);
      throw AiRuntimeServiceException(
        'Failed to send input to runtime command.',
        cause: exception,
        stackTrace: stackTrace,
      );
    }
  }

  /// Cancels the active runtime command.
  Future<void> cancel({int? aiSessionId}) async {
    _ensureNotDisposed();
    final sessionId = _resolveTargetSessionId(
      aiSessionId: aiSessionId,
      operation: 'cancel runtime',
    );
    final process = _activeProcesses[sessionId];
    final request = _activeLaunchRequests[sessionId];
    if (process == null || request == null) {
      throw AiRuntimeServiceException(
        'Cannot cancel because no runtime command is active for session $sessionId.',
      );
    }

    _cancelRequestedSessionIds.add(sessionId);
    try {
      await process.terminate();
    } on Exception catch (exception, stackTrace) {
      _emitErrorEvent(request, exception, stackTrace);
      throw AiRuntimeServiceException(
        'Failed to cancel runtime command.',
        cause: exception,
        stackTrace: stackTrace,
      );
    }

    final completion = await _cleanupActiveProcess(sessionId, process);
    if (completion == null) {
      return;
    }

    _emitEvent(
      AiRuntimeEvent(
        type: AiRuntimeEventType.cancelled,
        aiSessionId: completion.request.aiSessionId,
        connectionId: completion.request.connectionId,
        provider: completion.request.provider,
      ),
    );
  }

  /// Retries the last launched command.
  Future<void> retry({int? aiSessionId}) async {
    _ensureNotDisposed();
    final sessionId = _resolveRetrySessionId(aiSessionId);
    final previousRequest = _lastLaunchRequests[sessionId];
    if (previousRequest == null) {
      throw AiRuntimeServiceException(
        'Cannot retry because no previous runtime launch exists for session $sessionId.',
      );
    }
    if (hasActiveRunForSession(sessionId)) {
      throw AiRuntimeServiceException(
        'Cannot retry while another runtime command is active for session $sessionId.',
      );
    }

    _emitEvent(
      AiRuntimeEvent(
        type: AiRuntimeEventType.retried,
        aiSessionId: previousRequest.aiSessionId,
        connectionId: previousRequest.connectionId,
        provider: previousRequest.provider,
      ),
    );
    await launch(previousRequest);
  }

  /// Disposes this service and releases active process resources.
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;

    for (final entry in _activeProcesses.entries.toList(growable: false)) {
      final sessionId = entry.key;
      final activeProcess = entry.value;
      try {
        await activeProcess.terminate();
      } on Exception {
        // Continue cleanup regardless of terminate support/failure.
      }
      await _cleanupActiveProcess(sessionId, activeProcess);
    }

    await _eventsController.close();
  }

  void _attachOutputStreams(
    AiRuntimeProcess process,
    AiRuntimeLaunchRequest request,
  ) {
    final aiSessionId = request.aiSessionId;
    _stdoutSubscriptions[aiSessionId] = process.stdout.listen(
      (chunk) {
        _emitEvent(
          AiRuntimeEvent(
            type: AiRuntimeEventType.stdout,
            aiSessionId: request.aiSessionId,
            connectionId: request.connectionId,
            provider: request.provider,
            chunk: chunk,
          ),
        );
      },
      onError: (Object error, StackTrace stackTrace) {
        _emitErrorEvent(request, error, stackTrace);
      },
    );

    _stderrSubscriptions[aiSessionId] = process.stderr.listen(
      (chunk) {
        _emitEvent(
          AiRuntimeEvent(
            type: AiRuntimeEventType.stderr,
            aiSessionId: request.aiSessionId,
            connectionId: request.connectionId,
            provider: request.provider,
            chunk: chunk,
          ),
        );
      },
      onError: (Object error, StackTrace stackTrace) {
        _emitErrorEvent(request, error, stackTrace);
      },
    );
  }

  Future<void> _watchCompletion(
    int aiSessionId,
    AiRuntimeProcess process,
  ) async {
    try {
      await process.done;
    } on Exception catch (exception, stackTrace) {
      final request = _activeLaunchRequests[aiSessionId];
      if (request != null &&
          identical(_activeProcesses[aiSessionId], process)) {
        _emitErrorEvent(request, exception, stackTrace);
      }
    }

    if (!identical(_activeProcesses[aiSessionId], process)) {
      return;
    }

    final completion = await _cleanupActiveProcess(aiSessionId, process);
    if (completion == null) {
      return;
    }

    if (completion.wasCancelled) {
      _emitEvent(
        AiRuntimeEvent(
          type: AiRuntimeEventType.cancelled,
          aiSessionId: completion.request.aiSessionId,
          connectionId: completion.request.connectionId,
          provider: completion.request.provider,
        ),
      );
      return;
    }

    _emitEvent(
      AiRuntimeEvent(
        type: AiRuntimeEventType.completed,
        aiSessionId: completion.request.aiSessionId,
        connectionId: completion.request.connectionId,
        provider: completion.request.provider,
        exitCode: completion.exitCode,
      ),
    );

    final exitCode = completion.exitCode;
    if (exitCode != null && exitCode != 0) {
      _emitErrorEvent(
        completion.request,
        AiRuntimeServiceException(
          'Runtime command exited with code $exitCode.',
        ),
        StackTrace.current,
      );
    }
  }

  Future<_AiRuntimeCompletion?> _cleanupActiveProcess(
    int aiSessionId,
    AiRuntimeProcess process,
  ) async {
    if (!identical(_activeProcesses[aiSessionId], process)) {
      return null;
    }

    final request = _activeLaunchRequests[aiSessionId];
    if (request == null) {
      return null;
    }

    final completion = _AiRuntimeCompletion(
      request: request,
      exitCode: process.exitCode,
      wasCancelled: _cancelRequestedSessionIds.contains(aiSessionId),
    );

    await _stdoutSubscriptions.remove(aiSessionId)?.cancel();
    await _stderrSubscriptions.remove(aiSessionId)?.cancel();
    await process.close();

    _activeProcesses.remove(aiSessionId);
    _activeLaunchRequests.remove(aiSessionId);
    _cancelRequestedSessionIds.remove(aiSessionId);

    return completion;
  }

  Future<void> _cleanupDetachedProcess(AiRuntimeProcess process) async {
    try {
      await process.terminate();
    } on Exception {
      // Best-effort terminate; close still runs below.
    }
    await process.close();
  }

  void _emitErrorEvent(
    AiRuntimeLaunchRequest request,
    Object error,
    StackTrace stackTrace,
  ) => _emitEvent(
    AiRuntimeEvent(
      type: AiRuntimeEventType.error,
      aiSessionId: request.aiSessionId,
      connectionId: request.connectionId,
      provider: request.provider,
      error: error,
      stackTrace: stackTrace,
    ),
  );

  void _emitEvent(AiRuntimeEvent event) {
    if (_eventsController.isClosed) {
      return;
    }
    _eventsController.add(event);
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw const AiRuntimeServiceException(
        'AiRuntimeService is already disposed.',
      );
    }
  }

  int _resolveTargetSessionId({
    required int? aiSessionId,
    required String operation,
  }) {
    if (aiSessionId != null) {
      return aiSessionId;
    }
    if (_activeLaunchRequests.isEmpty) {
      throw const AiRuntimeServiceException(
        'Cannot complete operation because no runtime command is active.',
      );
    }
    if (_activeLaunchRequests.length > 1) {
      throw AiRuntimeServiceException(
        'Specify aiSessionId to $operation when multiple runtime commands are active.',
      );
    }
    return _activeLaunchRequests.keys.first;
  }

  int _resolveRetrySessionId(int? aiSessionId) {
    if (aiSessionId != null) {
      return aiSessionId;
    }
    if (_lastLaunchRequests.isEmpty) {
      throw const AiRuntimeServiceException(
        'Cannot retry because no previous runtime launch exists.',
      );
    }
    if (_lastLaunchRequests.length > 1) {
      throw const AiRuntimeServiceException(
        'Specify aiSessionId to retry when multiple launch histories exist.',
      );
    }
    return _lastLaunchRequests.keys.first;
  }
}

class _AiRuntimeCompletion {
  const _AiRuntimeCompletion({
    required this.request,
    required this.exitCode,
    required this.wasCancelled,
  });

  final AiRuntimeLaunchRequest request;
  final int? exitCode;
  final bool wasCancelled;
}

/// Provider for [AiRuntimeService].
final aiRuntimeServiceProvider = Provider<AiRuntimeService>((ref) {
  final activeSessions = ref.watch(activeSessionsProvider.notifier);
  final service = AiRuntimeService(
    shellResolver: ActiveSessionsAiRuntimeShellResolver(activeSessions),
  );
  ref.onDispose(() {
    unawaited(service.dispose());
  });
  return service;
});
