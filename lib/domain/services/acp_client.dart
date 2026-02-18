import 'dart:async';
import 'dart:convert';

import 'ai_runtime_service.dart';

/// JSON-RPC 2.0 client for the Agent Client Protocol (ACP).
///
/// Wraps an [AiRuntimeProcess] that speaks ACP over stdin/stdout.
/// All communication is newline-delimited JSON-RPC messages.
class AcpClient {
  /// Creates an [AcpClient] wrapping [process].
  AcpClient({required AiRuntimeProcess process}) : _process = process {
    _stdoutSubscription = _process.stdout.listen(
      _onStdoutChunk,
      onError: _onStreamError,
      onDone: _onStreamDone,
    );
  }

  final AiRuntimeProcess _process;
  StreamSubscription<String>? _stdoutSubscription;
  int _nextId = 1;
  final Map<int, Completer<Map<String, dynamic>>> _pendingRequests =
      <int, Completer<Map<String, dynamic>>>{};
  final StreamController<AcpEvent> _eventsController =
      StreamController<AcpEvent>.broadcast();
  String _stdoutBuffer = '';
  bool _disposed = false;

  /// Stream of ACP events (session updates, errors).
  Stream<AcpEvent> get events => _eventsController.stream;

  /// Agent info returned by [initialize].
  AcpAgentInfo? get agentInfo => _agentInfo;
  AcpAgentInfo? _agentInfo;

  /// Available models from the last [createSession] call.
  List<AcpModel> get availableModels =>
      List<AcpModel>.unmodifiable(_availableModels);
  final List<AcpModel> _availableModels = <AcpModel>[];

  /// Current model ID from the last [createSession] call.
  String? get currentModelId => _currentModelId;
  String? _currentModelId;

  /// Available modes from the last [createSession] call.
  List<AcpMode> get availableModes =>
      List<AcpMode>.unmodifiable(_availableModes);
  final List<AcpMode> _availableModes = <AcpMode>[];

  /// Current mode ID from the last [createSession] call.
  String? get currentModeId => _currentModeId;
  String? _currentModeId;

  /// Sends `initialize` and returns the agent capabilities.
  Future<Map<String, dynamic>> initialize({
    String clientName = 'MonkeySSH',
    String clientVersion = '1.0.0',
  }) async {
    final result = await _sendRequest('initialize', <String, dynamic>{
      'protocolVersion': 1,
      'clientInfo': <String, dynamic>{
        'name': clientName,
        'version': clientVersion,
      },
      'capabilities': <String, dynamic>{},
    });
    final agentInfoMap = result['agentInfo'];
    if (agentInfoMap is Map<String, dynamic>) {
      _agentInfo = AcpAgentInfo(
        name: agentInfoMap['name']?.toString() ?? 'Agent',
        title: agentInfoMap['title']?.toString(),
        version: agentInfoMap['version']?.toString(),
      );
    }
    return result;
  }

  /// Creates a new ACP session with [cwd] as the working directory.
  Future<AcpSession> createSession({required String cwd}) async {
    final result = await _sendRequest('session/new', <String, dynamic>{
      'cwd': cwd,
      'mcpServers': <dynamic>[],
    });

    final sessionId = result['sessionId']?.toString() ?? '';
    _parseModels(result);
    _parseModes(result);

    return AcpSession(
      sessionId: sessionId,
      availableModels: List<AcpModel>.unmodifiable(_availableModels),
      currentModelId: _currentModelId,
      availableModes: List<AcpMode>.unmodifiable(_availableModes),
      currentModeId: _currentModeId,
    );
  }

  /// Sends a user prompt to [sessionId] and waits for the response.
  ///
  /// Streaming updates are emitted on [events] as they arrive.
  /// Returns the final response result (e.g., `{"stopReason": "end_turn"}`).
  Future<Map<String, dynamic>> sendPrompt({
    required String sessionId,
    required String text,
    String? modelId,
  }) {
    final params = <String, dynamic>{
      'sessionId': sessionId,
      'prompt': <Map<String, dynamic>>[
        <String, dynamic>{'type': 'text', 'text': text},
      ],
    };
    if (modelId != null) {
      params['modelPreference'] = <String, dynamic>{'modelId': modelId};
    }
    return _sendRequest('session/prompt', params);
  }

  /// Disposes this client and releases resources.
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    await _stdoutSubscription?.cancel();
    _stdoutSubscription = null;

    for (final completer in _pendingRequests.values) {
      if (!completer.isCompleted) {
        completer.completeError(
          const AcpClientException('ACP client disposed while awaiting reply.'),
        );
      }
    }
    _pendingRequests.clear();
    await _eventsController.close();
  }

  Future<Map<String, dynamic>> _sendRequest(
    String method,
    Map<String, dynamic> params,
  ) {
    _ensureNotDisposed();
    final id = _nextId++;
    final message = <String, dynamic>{
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      'params': params,
    };
    final completer = Completer<Map<String, dynamic>>();
    _pendingRequests[id] = completer;
    _process.write('${jsonEncode(message)}\n');
    return completer.future;
  }

  void _onStdoutChunk(String chunk) {
    _stdoutBuffer += chunk;
    _drainBuffer();
  }

  void _drainBuffer() {
    while (true) {
      final newlineIndex = _stdoutBuffer.indexOf('\n');
      if (newlineIndex < 0) {
        break;
      }
      final line = _stdoutBuffer.substring(0, newlineIndex).trim();
      _stdoutBuffer = _stdoutBuffer.substring(newlineIndex + 1);
      if (line.isNotEmpty) {
        _handleJsonRpcLine(line);
      }
    }
  }

  void _handleJsonRpcLine(String line) {
    Map<String, dynamic> message;
    try {
      final decoded = jsonDecode(line);
      if (decoded is! Map<String, dynamic>) {
        return;
      }
      message = decoded;
    } on FormatException {
      return;
    }

    // Response to a request (has id + result/error).
    if (message.containsKey('id') &&
        (message.containsKey('result') || message.containsKey('error'))) {
      _handleResponse(message);
      return;
    }

    // Notification (no id, has method).
    if (message.containsKey('method') && !message.containsKey('id')) {
      _handleNotification(message);
      return;
    }
  }

  void _handleResponse(Map<String, dynamic> message) {
    final id = message['id'];
    if (id is! int) {
      return;
    }
    final completer = _pendingRequests.remove(id);
    if (completer == null || completer.isCompleted) {
      return;
    }
    final error = message['error'];
    if (error is Map<String, dynamic>) {
      completer.completeError(
        AcpClientException(
          error['message']?.toString() ?? 'ACP error',
          code: error['code'] is int ? error['code'] as int : null,
          data: error['data'],
        ),
      );
      return;
    }
    final result = message['result'];
    completer.complete(
      result is Map<String, dynamic> ? result : <String, dynamic>{},
    );
  }

  void _handleNotification(Map<String, dynamic> message) {
    final method = message['method']?.toString();
    final params = message['params'];
    if (method == null || params is! Map<String, dynamic>) {
      return;
    }

    if (method == 'session/update') {
      _handleSessionUpdate(params);
    }
  }

  void _handleSessionUpdate(Map<String, dynamic> params) {
    final sessionId = params['sessionId']?.toString() ?? '';
    final update = params['update'];
    if (update is! Map<String, dynamic>) {
      return;
    }

    final updateType = update['sessionUpdate']?.toString() ?? '';
    switch (updateType) {
      case 'agent_message_chunk':
        _emitEvent(
          AcpEvent(
            sessionId: sessionId,
            type: AcpEventType.agentMessage,
            text: _extractText(update['content']),
            rawUpdate: update,
          ),
        );
      case 'agent_thought_chunk':
        _emitEvent(
          AcpEvent(
            sessionId: sessionId,
            type: AcpEventType.agentThought,
            text: _extractText(update['content']),
            rawUpdate: update,
          ),
        );
      case 'tool_call':
        _emitEvent(
          AcpEvent(
            sessionId: sessionId,
            type: AcpEventType.toolCall,
            text: update['title']?.toString() ?? 'Tool call',
            toolCallId: update['toolCallId']?.toString(),
            rawUpdate: update,
          ),
        );
      case 'tool_call_update':
        _emitEvent(
          AcpEvent(
            sessionId: sessionId,
            type: AcpEventType.toolCallUpdate,
            text: _extractToolOutput(update),
            toolCallId: update['toolCallId']?.toString(),
            rawUpdate: update,
          ),
        );
      default:
        _emitEvent(
          AcpEvent(
            sessionId: sessionId,
            type: AcpEventType.unknown,
            text: updateType,
            rawUpdate: update,
          ),
        );
    }
  }

  String _extractText(Object? content) {
    if (content is Map<String, dynamic>) {
      return content['text']?.toString() ?? '';
    }
    if (content is String) {
      return content;
    }
    return '';
  }

  String _extractToolOutput(Map<String, dynamic> update) {
    final rawOutput = update['rawOutput'];
    if (rawOutput is Map<String, dynamic>) {
      final content = rawOutput['content'];
      if (content is String) {
        return content;
      }
      final detailedContent = rawOutput['detailedContent'];
      if (detailedContent is String) {
        return detailedContent;
      }
    }
    return update['status']?.toString() ?? '';
  }

  void _emitEvent(AcpEvent event) {
    if (!_eventsController.isClosed) {
      _eventsController.add(event);
    }
  }

  void _onStreamError(Object error, StackTrace stackTrace) {
    for (final completer in _pendingRequests.values) {
      if (!completer.isCompleted) {
        completer.completeError(error, stackTrace);
      }
    }
    _pendingRequests.clear();
  }

  void _onStreamDone() {
    for (final completer in _pendingRequests.values) {
      if (!completer.isCompleted) {
        completer.completeError(
          const AcpClientException('ACP process stdout stream closed.'),
        );
      }
    }
    _pendingRequests.clear();
  }

  void _parseModels(Map<String, dynamic> result) {
    _availableModels.clear();
    _currentModelId = null;
    final models = result['models'];
    if (models is! Map<String, dynamic>) {
      return;
    }
    _currentModelId = models['currentModelId']?.toString();
    final available = models['availableModels'];
    if (available is List<dynamic>) {
      for (final entry in available) {
        if (entry is Map<String, dynamic>) {
          _availableModels.add(
            AcpModel(
              modelId: entry['modelId']?.toString() ?? '',
              name: entry['name']?.toString() ?? '',
              description: entry['description']?.toString(),
            ),
          );
        }
      }
    }
  }

  void _parseModes(Map<String, dynamic> result) {
    _availableModes.clear();
    _currentModeId = null;
    final modes = result['modes'];
    if (modes is! Map<String, dynamic>) {
      return;
    }
    _currentModeId = modes['currentModeId']?.toString();
    final available = modes['availableModes'];
    if (available is List<dynamic>) {
      for (final entry in available) {
        if (entry is Map<String, dynamic>) {
          _availableModes.add(
            AcpMode(
              id: entry['id']?.toString() ?? '',
              name: entry['name']?.toString() ?? '',
              description: entry['description']?.toString(),
            ),
          );
        }
      }
    }
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw const AcpClientException('AcpClient is already disposed.');
    }
  }
}

/// Event types emitted by [AcpClient].
enum AcpEventType {
  /// Streaming text from the agent.
  agentMessage,

  /// Agent thinking/reasoning content.
  agentThought,

  /// Tool call initiated.
  toolCall,

  /// Tool call result.
  toolCallUpdate,

  /// Unrecognized session update type.
  unknown,
}

/// A single ACP event from a session update notification.
class AcpEvent {
  /// Creates an [AcpEvent].
  const AcpEvent({
    required this.sessionId,
    required this.type,
    required this.text,
    this.toolCallId,
    this.rawUpdate = const <String, dynamic>{},
  });

  /// ACP session ID this event belongs to.
  final String sessionId;

  /// Event type.
  final AcpEventType type;

  /// Text content for this event.
  final String text;

  /// Tool call identifier, if applicable.
  final String? toolCallId;

  /// Raw ACP update payload for metadata extraction.
  final Map<String, dynamic> rawUpdate;
}

/// Agent info returned by ACP initialize.
class AcpAgentInfo {
  /// Creates [AcpAgentInfo].
  const AcpAgentInfo({required this.name, this.title, this.version});

  /// Agent name.
  final String name;

  /// Agent display title.
  final String? title;

  /// Agent version string.
  final String? version;
}

/// ACP session returned by session/new.
class AcpSession {
  /// Creates an [AcpSession].
  const AcpSession({
    required this.sessionId,
    this.availableModels = const <AcpModel>[],
    this.currentModelId,
    this.availableModes = const <AcpMode>[],
    this.currentModeId,
  });

  /// Remote session identifier.
  final String sessionId;

  /// Models available in this session.
  final List<AcpModel> availableModels;

  /// Currently selected model ID.
  final String? currentModelId;

  /// Modes available in this session.
  final List<AcpMode> availableModes;

  /// Currently selected mode ID.
  final String? currentModeId;
}

/// Model metadata from ACP.
class AcpModel {
  /// Creates an [AcpModel].
  const AcpModel({required this.modelId, required this.name, this.description});

  /// Model identifier.
  final String modelId;

  /// Human-readable name.
  final String name;

  /// Optional description.
  final String? description;
}

/// Mode metadata from ACP.
class AcpMode {
  /// Creates an [AcpMode].
  const AcpMode({required this.id, required this.name, this.description});

  /// Mode identifier URI.
  final String id;

  /// Human-readable name.
  final String name;

  /// Optional description.
  final String? description;
}

/// Exception thrown by [AcpClient].
class AcpClientException implements Exception {
  /// Creates an [AcpClientException].
  const AcpClientException(this.message, {this.code, this.data});

  /// Human-readable error message.
  final String message;

  /// JSON-RPC error code, if available.
  final int? code;

  /// Additional error data, if available.
  final Object? data;

  @override
  String toString() => code == null
      ? 'AcpClientException: $message'
      : 'AcpClientException($code): $message';
}
