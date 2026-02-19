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
    _stderrSubscription = _process.stderr.listen(
      _onStderrChunk,
      onError: (_) {},
    );
  }

  final AiRuntimeProcess _process;
  StreamSubscription<String>? _stdoutSubscription;
  StreamSubscription<String>? _stderrSubscription;
  int _nextId = 1;
  final Map<int, Completer<Map<String, dynamic>>> _pendingRequests =
      <int, Completer<Map<String, dynamic>>>{};
  final StreamController<AcpEvent> _eventsController =
      StreamController<AcpEvent>.broadcast();
  String _stdoutBuffer = '';
  final StringBuffer _stderrBuffer = StringBuffer();
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
  final List<AcpCommand> _availableCommands = <AcpCommand>[];
  final Map<String, int> _activePromptRequestIdsBySession = <String, int>{};

  /// Available ACP commands from the latest session update.
  List<AcpCommand> get availableCommands =>
      List<AcpCommand>.unmodifiable(_availableCommands);

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
      'clientCapabilities': <String, dynamic>{},
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

  /// Creates a new ACP session.
  Future<AcpSession> createSession({required String cwd}) async {
    final normalizedCwd = cwd.trim();
    if (normalizedCwd.isEmpty || !normalizedCwd.startsWith('/')) {
      throw ArgumentError.value(
        cwd,
        'cwd',
        'ACP session cwd must be an absolute path.',
      );
    }
    final params = <String, dynamic>{
      'cwd': normalizedCwd,
      'mcpServers': <dynamic>[],
    };
    final result = await _sendRequest('session/new', params);

    final sessionId = result['sessionId']?.toString() ?? '';
    _parseModels(result);
    _parseModes(result);
    _parseCommands(result);

    return AcpSession(
      sessionId: sessionId,
      availableModels: List<AcpModel>.unmodifiable(_availableModels),
      currentModelId: _currentModelId,
      availableModes: List<AcpMode>.unmodifiable(_availableModes),
      currentModeId: _currentModeId,
      availableCommands: List<AcpCommand>.unmodifiable(_availableCommands),
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
  }) async {
    final params = <String, dynamic>{
      'sessionId': sessionId,
      'prompt': <Map<String, dynamic>>[
        <String, dynamic>{'type': 'text', 'text': text},
      ],
    };
    if (modelId != null) {
      params['modelPreference'] = <String, dynamic>{'modelId': modelId};
    }
    final pending = _sendRequestInternal('session/prompt', params);
    _activePromptRequestIdsBySession[sessionId] = pending.id;
    try {
      return await pending.future;
    } finally {
      final activeRequestId = _activePromptRequestIdsBySession[sessionId];
      if (activeRequestId == pending.id) {
        _activePromptRequestIdsBySession.remove(sessionId);
      }
    }
  }

  /// Requests an ACP mode switch for [sessionId].
  Future<Map<String, dynamic>> setMode({
    required String sessionId,
    required String modeId,
  }) => _sendRequest('session/set_mode', <String, dynamic>{
    'sessionId': sessionId,
    'modeId': modeId,
  });

  /// Requests an ACP model switch for [sessionId].
  Future<Map<String, dynamic>> setModel({
    required String sessionId,
    required String modelId,
  }) async {
    try {
      return await _sendRequest('session/set_config_option', <String, dynamic>{
        'sessionId': sessionId,
        'optionId': 'model',
        'value': modelId,
      });
    } on AcpClientException catch (error) {
      if (error.code == -32601) {
        return _sendRequest('session/set_model', <String, dynamic>{
          'sessionId': sessionId,
          'modelId': modelId,
        });
      }
      rethrow;
    }
  }

  /// Sends cancellation for an active prompt, if one exists.
  bool cancelActivePrompt(String sessionId) {
    if (!_activePromptRequestIdsBySession.containsKey(sessionId)) {
      return false;
    }
    _sendNotification('session/cancel', <String, dynamic>{
      'sessionId': sessionId,
    });
    return true;
  }

  /// Gracefully asks ACP agent to shutdown.
  Future<void> shutdown() async {
    try {
      await _sendRequest(
        'shutdown',
        const <String, dynamic>{},
      ).timeout(const Duration(milliseconds: 300));
    } on Exception {
      // Best effort.
    }
    try {
      _sendNotification('exit');
    } on Exception {
      // Best effort.
    }
  }

  /// Disposes this client and releases resources.
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    await shutdown();
    _disposed = true;
    await _stdoutSubscription?.cancel();
    _stdoutSubscription = null;
    await _stderrSubscription?.cancel();
    _stderrSubscription = null;

    for (final completer in _pendingRequests.values) {
      if (!completer.isCompleted) {
        completer.completeError(
          const AcpClientException('ACP client disposed while awaiting reply.'),
        );
      }
    }
    _pendingRequests.clear();
    _activePromptRequestIdsBySession.clear();
    await _eventsController.close();
  }

  Future<Map<String, dynamic>> _sendRequest(
    String method,
    Map<String, dynamic> params,
  ) => _sendRequestInternal(method, params).future;

  _AcpPendingRequest _sendRequestInternal(
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
    return _AcpPendingRequest(id: id, future: completer.future);
  }

  void _sendNotification(String method, [Map<String, dynamic>? params]) {
    _ensureNotDisposed();
    final message = <String, dynamic>{
      'jsonrpc': '2.0',
      'method': method,
      ...?(params == null ? null : <String, dynamic>{'params': params}),
    };
    _process.write('${jsonEncode(message)}\n');
  }

  void _onStdoutChunk(String chunk) {
    _stdoutBuffer += chunk;
    _drainBuffer();
  }

  void _drainBuffer() {
    if (_stdoutBuffer.isEmpty) {
      return;
    }
    final lines = _stdoutBuffer.split('\n');
    _stdoutBuffer = lines.removeLast();
    for (final rawLine in lines) {
      final line = rawLine.trim();
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
      case 'plan':
        _emitEvent(
          AcpEvent(
            sessionId: sessionId,
            type: AcpEventType.plan,
            text: _extractText(update['content']),
            rawUpdate: update,
          ),
        );
      case 'current_mode_update':
        final modeId = _extractModeId(update);
        if (modeId != null && modeId.isNotEmpty) {
          _currentModeId = modeId;
        }
        final availableModes = _extractAvailableModes(update);
        if (availableModes.isNotEmpty) {
          _availableModes
            ..clear()
            ..addAll(availableModes);
        }
        _emitEvent(
          AcpEvent(
            sessionId: sessionId,
            type: AcpEventType.currentModeUpdate,
            text: modeId ?? '',
            rawUpdate: update,
          ),
        );
      case 'current_model_update':
        final modelId = _extractModelId(update);
        if (modelId != null && modelId.isNotEmpty) {
          _currentModelId = modelId;
        }
        final availableModels = _extractAvailableModels(update);
        if (availableModels.isNotEmpty) {
          _availableModels
            ..clear()
            ..addAll(availableModels);
        }
        _emitEvent(
          AcpEvent(
            sessionId: sessionId,
            type: AcpEventType.currentModelUpdate,
            text: modelId ?? '',
            rawUpdate: update,
          ),
        );
      case 'available_commands_update':
        final commands = _extractAvailableCommands(update);
        _availableCommands
          ..clear()
          ..addAll(commands);
        _emitEvent(
          AcpEvent(
            sessionId: sessionId,
            type: AcpEventType.availableCommandsUpdate,
            text: '${commands.length} commands available',
            rawUpdate: update,
          ),
        );
      case 'session_info_update':
        _emitEvent(
          AcpEvent(
            sessionId: sessionId,
            type: AcpEventType.sessionInfoUpdate,
            text: update['title']?.toString() ?? 'Session info updated',
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
    if (content is List<dynamic>) {
      final parts = <String>[];
      for (final item in content) {
        if (item is Map<String, dynamic>) {
          final nested = item['content'];
          final extracted = switch (nested) {
            final Map<String, dynamic> value => value['text']?.toString() ?? '',
            final String value => value,
            _ => item['text']?.toString() ?? '',
          };
          if (extracted.trim().isNotEmpty) {
            parts.add(extracted.trim());
          }
        }
      }
      return parts.join('\n');
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
    final content = update['content'];
    final extractedContent = _extractText(content);
    if (extractedContent.trim().isNotEmpty) {
      return extractedContent;
    }
    return update['status']?.toString() ?? '';
  }

  String? _extractModeId(Map<String, dynamic> update) {
    final modes = update['modes'];
    final value =
        update['modeId'] ??
        update['currentModeId'] ??
        (modes is Map<String, dynamic> ? modes['currentModeId'] : null);
    final modeId = value?.toString();
    return modeId != null && modeId.trim().isNotEmpty ? modeId : null;
  }

  String? _extractModelId(Map<String, dynamic> update) {
    final models = update['models'];
    final value =
        update['modelId'] ??
        update['currentModelId'] ??
        (models is Map<String, dynamic> ? models['currentModelId'] : null);
    final modelId = value?.toString();
    return modelId != null && modelId.trim().isNotEmpty ? modelId : null;
  }

  List<AcpMode> _extractAvailableModes(Map<String, dynamic> update) {
    final availableValue = update['availableModes'] ?? update['modes'];
    final available = switch (availableValue) {
      final List<dynamic> value => value,
      final Map<String, dynamic> value =>
        value['availableModes'] is List<dynamic>
            ? value['availableModes'] as List<dynamic>
            : const <dynamic>[],
      _ => const <dynamic>[],
    };
    final modes = <AcpMode>[];
    for (final entry in available) {
      if (entry is Map<String, dynamic>) {
        final modeId =
            entry['id']?.toString() ?? entry['modeId']?.toString() ?? '';
        if (modeId.trim().isEmpty) {
          continue;
        }
        final modeName = entry['name']?.toString();
        modes.add(
          AcpMode(
            id: modeId,
            name: modeName?.trim().isNotEmpty ?? false ? modeName! : modeId,
            description: entry['description']?.toString(),
          ),
        );
      } else if (entry is String && entry.trim().isNotEmpty) {
        modes.add(AcpMode(id: entry.trim(), name: entry.trim()));
      }
    }
    return modes;
  }

  List<AcpModel> _extractAvailableModels(Map<String, dynamic> update) {
    final availableValue = update['availableModels'] ?? update['models'];
    final available = switch (availableValue) {
      final List<dynamic> value => value,
      final Map<String, dynamic> value =>
        value['availableModels'] is List<dynamic>
            ? value['availableModels'] as List<dynamic>
            : const <dynamic>[],
      _ => const <dynamic>[],
    };
    final models = <AcpModel>[];
    for (final entry in available) {
      if (entry is Map<String, dynamic>) {
        final modelId =
            entry['modelId']?.toString() ?? entry['id']?.toString() ?? '';
        if (modelId.trim().isEmpty) {
          continue;
        }
        final modelName = entry['name']?.toString();
        models.add(
          AcpModel(
            modelId: modelId,
            name: modelName?.trim().isNotEmpty ?? false ? modelName! : modelId,
            description: entry['description']?.toString(),
          ),
        );
      } else if (entry is String && entry.trim().isNotEmpty) {
        models.add(AcpModel(modelId: entry.trim(), name: entry.trim()));
      }
    }
    return models;
  }

  List<AcpCommand> _extractAvailableCommands(Map<String, dynamic> update) {
    final commandsValue = update['commands'] ?? update['availableCommands'];
    final commands = switch (commandsValue) {
      final List<dynamic> value => value,
      final Map<String, dynamic> value =>
        value['availableCommands'] is List<dynamic>
            ? value['availableCommands'] as List<dynamic>
            : const <dynamic>[],
      _ => const <dynamic>[],
    };
    if (commands.isEmpty) {
      return const <AcpCommand>[];
    }
    final parsed = <AcpCommand>[];
    for (final entry in commands) {
      if (entry is Map<String, dynamic>) {
        final id = entry['name']?.toString() ?? entry['id']?.toString() ?? '';
        final normalizedId = id.trim();
        if (normalizedId.isEmpty) {
          continue;
        }
        final title =
            entry['title']?.toString() ??
            entry['name']?.toString() ??
            normalizedId;
        parsed.add(
          AcpCommand(
            id: normalizedId,
            title: title.trim().isEmpty ? normalizedId : title,
            description: entry['description']?.toString(),
          ),
        );
      } else if (entry is String && entry.trim().isNotEmpty) {
        parsed.add(AcpCommand(id: entry.trim(), title: entry.trim()));
      }
    }
    return parsed;
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
    _activePromptRequestIdsBySession.clear();
  }

  void _onStderrChunk(String chunk) {
    _stderrBuffer.write(chunk);
  }

  void _onStreamDone() {
    final stderrContent = _stderrBuffer.toString().trim();
    final errorMessage = stderrContent.isNotEmpty
        ? 'ACP process ended: $stderrContent'
        : 'ACP process stdout stream closed.';
    for (final completer in _pendingRequests.values) {
      if (!completer.isCompleted) {
        completer.completeError(AcpClientException(errorMessage));
      }
    }
    _pendingRequests.clear();
    _activePromptRequestIdsBySession.clear();
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

  void _parseCommands(Map<String, dynamic> result) {
    _availableCommands
      ..clear()
      ..addAll(_extractAvailableCommands(result));
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

  /// Agent plan update.
  plan,

  /// Current mode changed.
  currentModeUpdate,

  /// Current model changed.
  currentModelUpdate,

  /// Available ACP commands changed.
  availableCommandsUpdate,

  /// Session info metadata changed.
  sessionInfoUpdate,

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
    this.availableCommands = const <AcpCommand>[],
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

  /// ACP commands available for this session.
  final List<AcpCommand> availableCommands;
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

/// Command metadata from ACP available-commands updates.
class AcpCommand {
  /// Creates an [AcpCommand].
  const AcpCommand({required this.id, required this.title, this.description});

  /// Stable command identifier.
  final String id;

  /// Human-readable title.
  final String title;

  /// Optional command description.
  final String? description;
}

class _AcpPendingRequest {
  const _AcpPendingRequest({required this.id, required this.future});

  final int id;
  final Future<Map<String, dynamic>> future;
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

  String _formatData() {
    if (data == null) {
      return '';
    }
    final serialized = switch (data) {
      final String value => value,
      _ => jsonEncode(data),
    };
    const maxLength = 600;
    final clipped = serialized.length > maxLength
        ? '${serialized.substring(0, maxLength)}…'
        : serialized;
    return ' data=$clipped';
  }

  @override
  String toString() => code == null
      ? 'AcpClientException: $message${_formatData()}'
      : 'AcpClientException($code): $message${_formatData()}';
}
