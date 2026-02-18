// ignore_for_file: public_member_api_docs

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:monkeyssh/domain/models/ai_cli_provider.dart';
import 'package:monkeyssh/domain/services/ai_runtime_service.dart';

void main() {
  group('AiRuntimeService', () {
    test('launch runs command and streams stdout/stderr events', () async {
      final process = _FakeRuntimeProcess();
      final shell = _FakeRuntimeShell(
        processes: <_FakeRuntimeProcess>[process],
      );
      final service = AiRuntimeService(
        shellResolver: _FakeRuntimeShellResolver(<int, AiRuntimeShell>{
          42: shell,
        }),
      );
      addTearDown(service.dispose);

      final events = <AiRuntimeEvent>[];
      final errors = <Object>[];
      final subscription = service.events.listen(
        events.add,
        onError: errors.add,
      );
      addTearDown(subscription.cancel);
      final completionEventFuture = service.events.firstWhere(
        (event) => event.type == AiRuntimeEventType.completed,
      );

      const request = AiRuntimeLaunchRequest(
        aiSessionId: 7,
        connectionId: 42,
        provider: AiCliProvider.codex,
        remoteWorkingDirectory: '/srv/project',
      );
      await service.launch(request);
      process
        ..emitStdout('hello')
        ..emitStderr('warning');
      await process.finish(exitCode: 0);
      await completionEventFuture;

      expect(shell.executedCommands, const <String>[
        'cd \'/srv/project\' && codex',
      ]);
      expect(
        events.map((event) => event.type),
        containsAllInOrder(<AiRuntimeEventType>[
          AiRuntimeEventType.started,
          AiRuntimeEventType.stdout,
          AiRuntimeEventType.stderr,
          AiRuntimeEventType.completed,
        ]),
      );
      expect(
        events
            .where((event) => event.type == AiRuntimeEventType.stdout)
            .single
            .chunk,
        'hello',
      );
      expect(
        events
            .where((event) => event.type == AiRuntimeEventType.stderr)
            .single
            .chunk,
        'warning',
      );
      expect(errors, isEmpty);
    });

    test('launch runs copilot without forcing PTY mode', () async {
      final process = _FakeRuntimeProcess();
      final shell = _FakeRuntimeShell(
        processes: <_FakeRuntimeProcess>[process],
      );
      final service = AiRuntimeService(
        shellResolver: _FakeRuntimeShellResolver(<int, AiRuntimeShell>{
          88: shell,
        }),
      );
      addTearDown(service.dispose);

      await service.launch(
        const AiRuntimeLaunchRequest(
          aiSessionId: 12,
          connectionId: 88,
          provider: AiCliProvider.copilot,
          remoteWorkingDirectory: '/repo',
        ),
      );

      expect(shell.executedRunInPty, const <bool>[false]);
    });

    test('launch runs ACP overrides without forcing PTY mode', () async {
      final process = _FakeRuntimeProcess();
      final shell = _FakeRuntimeShell(
        processes: <_FakeRuntimeProcess>[process],
      );
      final service = AiRuntimeService(
        shellResolver: _FakeRuntimeShellResolver(<int, AiRuntimeShell>{
          89: shell,
        }),
      );
      addTearDown(service.dispose);

      await service.launch(
        const AiRuntimeLaunchRequest(
          aiSessionId: 13,
          connectionId: 89,
          provider: AiCliProvider.acp,
          executableOverride: 'copilot --acp',
          remoteWorkingDirectory: '/repo',
        ),
      );

      expect(shell.executedRunInPty, const <bool>[false]);
    });

    test('send writes to stdin and throws when runtime is inactive', () async {
      final process = _FakeRuntimeProcess();
      final shell = _FakeRuntimeShell(
        processes: <_FakeRuntimeProcess>[process],
      );
      final service = AiRuntimeService(
        shellResolver: _FakeRuntimeShellResolver(<int, AiRuntimeShell>{
          99: shell,
        }),
      );
      addTearDown(service.dispose);

      await service.launch(
        const AiRuntimeLaunchRequest(
          aiSessionId: 11,
          connectionId: 99,
          provider: AiCliProvider.claude,
          remoteWorkingDirectory: '/repo',
        ),
      );
      await service.send('test-input', appendNewline: true);
      expect(process.writes, const <String>['test-input\n']);

      await process.finish(exitCode: 0);
      await Future<void>.delayed(Duration.zero);

      await expectLater(
        () => service.send('later'),
        throwsA(isA<AiRuntimeServiceException>()),
      );
    });

    test(
      'cancel terminates active process and emits cancelled event',
      () async {
        final process = _FakeRuntimeProcess();
        final shell = _FakeRuntimeShell(
          processes: <_FakeRuntimeProcess>[process],
        );
        final service = AiRuntimeService(
          shellResolver: _FakeRuntimeShellResolver(<int, AiRuntimeShell>{
            5: shell,
          }),
        );
        addTearDown(service.dispose);

        final cancelledEventFuture = service.events.firstWhere(
          (event) => event.type == AiRuntimeEventType.cancelled,
        );
        await service.launch(
          const AiRuntimeLaunchRequest(
            aiSessionId: 3,
            connectionId: 5,
            provider: AiCliProvider.gemini,
            remoteWorkingDirectory: '/workspace',
          ),
        );
        await service.cancel();
        final cancelled = await cancelledEventFuture;

        expect(cancelled.connectionId, 5);
        expect(process.terminated, isTrue);
        expect(process.closed, isTrue);
        expect(service.hasActiveRun, isFalse);
      },
    );

    test('retry relaunches previous request after completion', () async {
      final firstProcess = _FakeRuntimeProcess();
      final secondProcess = _FakeRuntimeProcess();
      final shell = _FakeRuntimeShell(
        processes: <_FakeRuntimeProcess>[firstProcess, secondProcess],
      );
      final service = AiRuntimeService(
        shellResolver: _FakeRuntimeShellResolver(<int, AiRuntimeShell>{
          17: shell,
        }),
      );
      addTearDown(service.dispose);

      const request = AiRuntimeLaunchRequest(
        aiSessionId: 21,
        connectionId: 17,
        provider: AiCliProvider.claude,
        remoteWorkingDirectory: '/repo',
      );

      await service.launch(request);
      await firstProcess.finish(exitCode: 0);
      await Future<void>.delayed(Duration.zero);
      await service.retry();
      await secondProcess.finish(exitCode: 0);
      await Future<void>.delayed(Duration.zero);

      expect(shell.executedCommands, hasLength(2));
      expect(shell.executedCommands.first, shell.executedCommands.last);
    });

    test('supports multiple active sessions concurrently', () async {
      final firstProcess = _FakeRuntimeProcess();
      final secondProcess = _FakeRuntimeProcess();
      final shell = _FakeRuntimeShell(
        processes: <_FakeRuntimeProcess>[firstProcess, secondProcess],
      );
      final service = AiRuntimeService(
        shellResolver: _FakeRuntimeShellResolver(<int, AiRuntimeShell>{
          55: shell,
        }),
      );
      addTearDown(service.dispose);

      await service.launch(
        const AiRuntimeLaunchRequest(
          aiSessionId: 101,
          connectionId: 55,
          provider: AiCliProvider.codex,
          remoteWorkingDirectory: '/repo-one',
        ),
      );
      await service.launch(
        const AiRuntimeLaunchRequest(
          aiSessionId: 202,
          connectionId: 55,
          provider: AiCliProvider.claude,
          remoteWorkingDirectory: '/repo-two',
        ),
      );

      await service.send('first', appendNewline: true, aiSessionId: 101);
      await service.send('second', appendNewline: true, aiSessionId: 202);
      expect(firstProcess.writes, const <String>['first\n']);
      expect(secondProcess.writes, const <String>['second\n']);
      await expectLater(
        () => service.send('ambiguous', appendNewline: true),
        throwsA(isA<AiRuntimeServiceException>()),
      );

      await firstProcess.finish(exitCode: 0);
      await secondProcess.finish(exitCode: 0);
    });

    test(
      'non-zero exit publishes error events without stream errors',
      () async {
        final process = _FakeRuntimeProcess();
        final shell = _FakeRuntimeShell(
          processes: <_FakeRuntimeProcess>[process],
        );
        final service = AiRuntimeService(
          shellResolver: _FakeRuntimeShellResolver(<int, AiRuntimeShell>{
            66: shell,
          }),
        );
        addTearDown(service.dispose);

        final events = <AiRuntimeEvent>[];
        final streamErrors = <Object>[];
        final subscription = service.events.listen(
          events.add,
          onError: streamErrors.add,
        );
        addTearDown(subscription.cancel);

        await service.launch(
          const AiRuntimeLaunchRequest(
            aiSessionId: 1,
            connectionId: 66,
            provider: AiCliProvider.codex,
            remoteWorkingDirectory: '/tmp/repo',
          ),
        );
        await process.finish(exitCode: 12);
        await Future<void>.delayed(Duration.zero);

        expect(
          events.where((event) => event.type == AiRuntimeEventType.error),
          isNotEmpty,
        );
        expect(streamErrors, isEmpty);
      },
    );

    test(
      'launch prevents concurrent launches while first launch is pending',
      () async {
        final process = _FakeRuntimeProcess();
        final shell = _BlockingRuntimeShell(process);
        final service = AiRuntimeService(
          shellResolver: _FakeRuntimeShellResolver(<int, AiRuntimeShell>{
            77: shell,
          }),
        );
        addTearDown(service.dispose);

        final firstLaunch = service.launch(
          const AiRuntimeLaunchRequest(
            aiSessionId: 2,
            connectionId: 77,
            provider: AiCliProvider.claude,
            remoteWorkingDirectory: '/repo',
          ),
        );
        await Future<void>.delayed(Duration.zero);

        await expectLater(
          () => service.launch(
            const AiRuntimeLaunchRequest(
              aiSessionId: 2,
              connectionId: 77,
              provider: AiCliProvider.claude,
              remoteWorkingDirectory: '/repo',
            ),
          ),
          throwsA(isA<AiRuntimeServiceException>()),
        );

        shell.release();
        await firstLaunch;
        await process.finish(exitCode: 0);
      },
    );

    test('dispose terminates active process before cleanup', () async {
      final process = _FakeRuntimeProcess();
      final shell = _FakeRuntimeShell(
        processes: <_FakeRuntimeProcess>[process],
      );
      final service = AiRuntimeService(
        shellResolver: _FakeRuntimeShellResolver(<int, AiRuntimeShell>{
          34: shell,
        }),
      );

      await service.launch(
        const AiRuntimeLaunchRequest(
          aiSessionId: 3,
          connectionId: 34,
          provider: AiCliProvider.codex,
          remoteWorkingDirectory: '/repo',
        ),
      );
      await service.dispose();

      expect(process.terminated, isTrue);
      expect(process.closed, isTrue);
    });

    test('launch/retry validate session and history preconditions', () async {
      final service = AiRuntimeService(
        shellResolver: const _FakeRuntimeShellResolver(<int, AiRuntimeShell>{}),
      );
      addTearDown(service.dispose);

      await expectLater(
        () => service.launch(
          const AiRuntimeLaunchRequest(
            aiSessionId: 4,
            connectionId: 999,
            provider: AiCliProvider.copilot,
            remoteWorkingDirectory: '/repo',
          ),
        ),
        throwsA(isA<AiRuntimeServiceException>()),
      );

      await expectLater(
        service.retry,
        throwsA(isA<AiRuntimeServiceException>()),
      );
    });
  });
}

class _FakeRuntimeShellResolver implements AiRuntimeShellResolver {
  const _FakeRuntimeShellResolver(this._shellByConnectionId);

  final Map<int, AiRuntimeShell> _shellByConnectionId;

  @override
  AiRuntimeShell? resolve(int connectionId) =>
      _shellByConnectionId[connectionId];
}

class _FakeRuntimeShell implements AiRuntimeShell {
  _FakeRuntimeShell({required List<_FakeRuntimeProcess> processes})
    : _processes = processes;

  final List<_FakeRuntimeProcess> _processes;
  final List<String> executedCommands = <String>[];
  final List<bool> executedRunInPty = <bool>[];

  @override
  Future<AiRuntimeProcess> execute(
    String command, {
    bool runInPty = false,
  }) async {
    executedCommands.add(command);
    executedRunInPty.add(runInPty);
    if (_processes.isEmpty) {
      throw Exception('No fake process available');
    }
    return _processes.removeAt(0);
  }
}

class _BlockingRuntimeShell implements AiRuntimeShell {
  _BlockingRuntimeShell(this._process);

  final _gate = Completer<void>();
  final _FakeRuntimeProcess _process;

  @override
  Future<AiRuntimeProcess> execute(
    String command, {
    bool runInPty = false,
  }) async {
    await _gate.future;
    return _process;
  }

  void release() {
    if (!_gate.isCompleted) {
      _gate.complete();
    }
  }
}

class _FakeRuntimeProcess implements AiRuntimeProcess {
  final StreamController<String> _stdoutController =
      StreamController<String>.broadcast();
  final StreamController<String> _stderrController =
      StreamController<String>.broadcast();
  final Completer<void> _doneCompleter = Completer<void>();
  final List<String> writes = <String>[];
  int? _exitCode;
  bool terminated = false;
  bool closed = false;

  @override
  Stream<String> get stdout => _stdoutController.stream;

  @override
  Stream<String> get stderr => _stderrController.stream;

  @override
  Future<void> get done => _doneCompleter.future;

  @override
  int? get exitCode => _exitCode;

  @override
  void write(String input) {
    writes.add(input);
  }

  @override
  Future<void> terminate() async {
    terminated = true;
    await finish(exitCode: 143);
  }

  @override
  Future<void> close() async {
    closed = true;
    await _closeControllers();
    if (!_doneCompleter.isCompleted) {
      _doneCompleter.complete();
    }
  }

  void emitStdout(String chunk) {
    _stdoutController.add(chunk);
  }

  void emitStderr(String chunk) {
    _stderrController.add(chunk);
  }

  Future<void> finish({int? exitCode}) async {
    _exitCode = exitCode;
    await _closeControllers();
    if (!_doneCompleter.isCompleted) {
      _doneCompleter.complete();
    }
  }

  Future<void> _closeControllers() async {
    if (!_stdoutController.isClosed) {
      await _stdoutController.close();
    }
    if (!_stderrController.isClosed) {
      await _stderrController.close();
    }
  }
}
