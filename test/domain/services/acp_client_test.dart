// ignore_for_file: public_member_api_docs

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:monkeyssh/domain/services/acp_client.dart';
import 'package:monkeyssh/domain/services/ai_runtime_service.dart';

/// Fake process that lets tests inject stdout lines and read stdin writes.
class _FakeAiRuntimeProcess implements AiRuntimeProcess {
  final StreamController<String> _stdoutController =
      StreamController<String>.broadcast();
  final StreamController<String> _stderrController =
      StreamController<String>.broadcast();
  final Completer<void> _doneCompleter = Completer<void>();
  final List<String> stdinWrites = <String>[];

  @override
  Stream<String> get stdout => _stdoutController.stream;

  @override
  Stream<String> get stderr => _stderrController.stream;

  @override
  Future<void> get done => _doneCompleter.future;

  @override
  int? get exitCode => null;

  @override
  void write(String input) {
    stdinWrites.add(input);
  }

  @override
  Future<void> terminate() async {}

  @override
  Future<void> close() async {}

  void emitStdout(String data) {
    _stdoutController.add(data);
  }

  void completeProcess() {
    _doneCompleter.complete();
    _stdoutController.close();
    _stderrController.close();
  }
}

void main() {
  group('AcpClient', () {
    late _FakeAiRuntimeProcess process;
    late AcpClient client;

    setUp(() {
      process = _FakeAiRuntimeProcess();
      client = AcpClient(process: process);
    });

    tearDown(() async {
      await client.dispose();
    });

    test('initialize sends JSON-RPC initialize and parses agent info', () async {
      final initFuture = client.initialize();

      // Give microtask a chance to write.
      await Future<void>.delayed(Duration.zero);
      expect(process.stdinWrites, hasLength(1));
      final sent =
          jsonDecode(process.stdinWrites.first) as Map<String, dynamic>;
      expect(sent['method'], 'initialize');
      expect(sent['id'], 1);
      final params = sent['params'] as Map<String, dynamic>;
      expect(params, contains('clientCapabilities'));
      expect(params, isNot(contains('capabilities')));

      process.emitStdout(
        '${jsonEncode(<String, dynamic>{
          'jsonrpc': '2.0',
          'id': 1,
          'result': <String, dynamic>{
            'protocolVersion': 1,
            'agentInfo': <String, dynamic>{'name': 'TestAgent', 'title': 'Test Agent', 'version': '0.1.0'},
          },
        })}\n',
      );

      final result = await initFuture;
      expect(result['protocolVersion'], 1);
      expect(client.agentInfo?.name, 'TestAgent');
      expect(client.agentInfo?.title, 'Test Agent');
      expect(client.agentInfo?.version, '0.1.0');
    });

    test('createSession sends session/new and parses models', () async {
      // First initialize.
      final initFuture = client.initialize();
      await Future<void>.delayed(Duration.zero);
      process.emitStdout(
        '${jsonEncode(<String, dynamic>{
          'jsonrpc': '2.0',
          'id': 1,
          'result': <String, dynamic>{'protocolVersion': 1},
        })}\n',
      );
      await initFuture;

      final sessionFuture = client.createSession(cwd: '/test');
      await Future<void>.delayed(Duration.zero);
      expect(process.stdinWrites, hasLength(2));
      final sent = jsonDecode(process.stdinWrites[1]) as Map<String, dynamic>;
      expect(sent['method'], 'session/new');
      final sentParams = sent['params'] as Map<String, dynamic>;
      expect(sentParams['cwd'], '/test');

      process.emitStdout(
        '${jsonEncode(<String, dynamic>{
          'jsonrpc': '2.0',
          'id': 2,
          'result': <String, dynamic>{
            'sessionId': 'test-session-id',
            'models': <String, dynamic>{
              'currentModelId': 'model-a',
              'availableModels': <dynamic>[
                <String, dynamic>{'modelId': 'model-a', 'name': 'Model A'},
                <String, dynamic>{'modelId': 'model-b', 'name': 'Model B'},
              ],
            },
            'modes': <String, dynamic>{
              'currentModeId': 'agent',
              'availableModes': <dynamic>[
                <String, dynamic>{'id': 'agent', 'name': 'Agent'},
              ],
            },
          },
        })}\n',
      );

      final session = await sessionFuture;
      expect(session.sessionId, 'test-session-id');
      expect(session.currentModelId, 'model-a');
      expect(session.availableModels, hasLength(2));
      expect(session.availableModes, hasLength(1));
      expect(client.availableModels, hasLength(2));
    });

    test('sendPrompt returns result and emits streaming events', () async {
      // Initialize.
      final initFuture = client.initialize();
      await Future<void>.delayed(Duration.zero);
      process.emitStdout(
        '${jsonEncode(<String, dynamic>{
          'jsonrpc': '2.0',
          'id': 1,
          'result': <String, dynamic>{'protocolVersion': 1},
        })}\n',
      );
      await initFuture;

      // Create session.
      final sessionFuture = client.createSession(cwd: '/test');
      await Future<void>.delayed(Duration.zero);
      process.emitStdout(
        '${jsonEncode(<String, dynamic>{
          'jsonrpc': '2.0',
          'id': 2,
          'result': <String, dynamic>{'sessionId': 'sess-1', 'models': <String, dynamic>{}, 'modes': <String, dynamic>{}},
        })}\n',
      );
      await sessionFuture;

      // Send prompt and collect events.
      final collectedEvents = <AcpEvent>[];
      final eventSub = client.events.listen(collectedEvents.add);

      final promptFuture = client.sendPrompt(
        sessionId: 'sess-1',
        text: 'hello',
      );
      await Future<void>.delayed(Duration.zero);

      // Emit thinking notification.
      process
        ..emitStdout(
          '${jsonEncode(<String, dynamic>{
            'jsonrpc': '2.0',
            'method': 'session/update',
            'params': <String, dynamic>{
              'sessionId': 'sess-1',
              'update': <String, dynamic>{
                'sessionUpdate': 'agent_thought_chunk',
                'content': <String, dynamic>{'type': 'text', 'text': 'Thinking...'},
              },
            },
          })}\n',
        )
        // Emit tool call notification.
        ..emitStdout(
          '${jsonEncode(<String, dynamic>{
            'jsonrpc': '2.0',
            'method': 'session/update',
            'params': <String, dynamic>{
              'sessionId': 'sess-1',
              'update': <String, dynamic>{'sessionUpdate': 'tool_call', 'toolCallId': 'tc-1', 'title': 'Reading file', 'kind': 'read', 'status': 'pending'},
            },
          })}\n',
        )
        // Emit message chunk.
        ..emitStdout(
          '${jsonEncode(<String, dynamic>{
            'jsonrpc': '2.0',
            'method': 'session/update',
            'params': <String, dynamic>{
              'sessionId': 'sess-1',
              'update': <String, dynamic>{
                'sessionUpdate': 'agent_message_chunk',
                'content': <String, dynamic>{'type': 'text', 'text': 'Hello world'},
              },
            },
          })}\n',
        )
        // Emit final response.
        ..emitStdout(
          '${jsonEncode(<String, dynamic>{
            'jsonrpc': '2.0',
            'id': 3,
            'result': <String, dynamic>{'stopReason': 'end_turn'},
          })}\n',
        );

      final result = await promptFuture;
      expect(result['stopReason'], 'end_turn');

      await eventSub.cancel();

      expect(collectedEvents, hasLength(3));
      expect(collectedEvents[0].type, AcpEventType.agentThought);
      expect(collectedEvents[0].text, 'Thinking...');
      expect(collectedEvents[1].type, AcpEventType.toolCall);
      expect(collectedEvents[1].toolCallId, 'tc-1');
      expect(collectedEvents[1].text, 'Reading file');
      expect(collectedEvents[2].type, AcpEventType.agentMessage);
      expect(collectedEvents[2].text, 'Hello world');
    });

    test('handles JSON-RPC errors gracefully', () async {
      final initFuture = client.initialize();
      await Future<void>.delayed(Duration.zero);
      process.emitStdout(
        '${jsonEncode(<String, dynamic>{
          'jsonrpc': '2.0',
          'id': 1,
          'error': <String, dynamic>{'code': -32603, 'message': 'Internal error'},
        })}\n',
      );

      expect(initFuture, throwsA(isA<AcpClientException>()));
    });

    test('handles partial stdout lines across chunks', () async {
      final initFuture = client.initialize();
      await Future<void>.delayed(Duration.zero);

      final fullLine = jsonEncode(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': 1,
        'result': <String, dynamic>{'protocolVersion': 1},
      });

      // Send partial then rest.
      process.emitStdout(fullLine.substring(0, 10));
      await Future<void>.delayed(Duration.zero);

      process.emitStdout('${fullLine.substring(10)}\n');
      final result = await initFuture;
      expect(result['protocolVersion'], 1);
    });

    test('dispose completes pending requests with error', () async {
      // Use a separate client that we manually dispose (not in tearDown).
      final localProcess = _FakeAiRuntimeProcess();
      final localClient = AcpClient(process: localProcess);

      final initFuture = localClient.initialize().catchError(
        (_) => <String, dynamic>{},
      );
      await Future<void>.delayed(Duration.zero);

      await localClient.dispose();
      // If dispose didn't error the pending request, initFuture would hang.
      // The catchError above handles the expected AcpClientException.
      final result = await initFuture;
      expect(result, isEmpty);
    });
  });
}
