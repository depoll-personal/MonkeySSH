import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/ai_cli_provider.dart';
import 'ai_runtime_service.dart';

/// Normalized timeline event kinds for AI runtime output.
enum AiTimelineEventType {
  /// User or assistant text message.
  message,

  /// Tool invocation or tool result output.
  tool,

  /// Model reasoning/thinking content.
  thinking,

  /// Runtime lifecycle/status updates.
  status,

  /// Error output.
  error,
}

/// Timeline-ready event parsed from AI runtime output.
class AiTimelineEvent {
  /// Creates an [AiTimelineEvent].
  const AiTimelineEvent({
    required this.type,
    required this.aiSessionId,
    required this.connectionId,
    required this.provider,
    required this.message,
    this.metadata = const <String, dynamic>{},
  });

  /// Normalized event type for rendering.
  final AiTimelineEventType type;

  /// AI session associated with this timeline event.
  final int aiSessionId;

  /// SSH connection associated with this timeline event.
  final int connectionId;

  /// Provider that produced the event.
  final AiCliProvider provider;

  /// Human-readable event message.
  final String message;

  /// Additional provider-specific metadata.
  final Map<String, dynamic> metadata;
}

/// Provider-specific adapter used to normalize structured payloads.
abstract interface class AiRuntimeProviderEventAdapter {
  /// Parses one structured provider payload into normalized timeline events.
  List<AiTimelineEvent> parseStructuredPayload({
    required Map<String, dynamic> payload,
    required AiRuntimeEvent runtimeEvent,
  });
}

/// Pipeline that transforms [AiRuntimeEvent] streams into [AiTimelineEvent].
class AiRuntimeEventParserPipeline {
  /// Creates an [AiRuntimeEventParserPipeline].
  AiRuntimeEventParserPipeline({
    Map<AiCliProvider, AiRuntimeProviderEventAdapter>? adapters,
  }) : _adapters = adapters ?? _defaultAdapters;

  static const AiRuntimeProviderEventAdapter _fallbackAdapter =
      _DefaultAiRuntimeProviderEventAdapter();
  static const Map<AiCliProvider, AiRuntimeProviderEventAdapter>
  _defaultAdapters = <AiCliProvider, AiRuntimeProviderEventAdapter>{
    AiCliProvider.claude: _ClaudeAiRuntimeProviderEventAdapter(),
    AiCliProvider.codex: _CodexAiRuntimeProviderEventAdapter(),
    AiCliProvider.opencode: _OpenCodeAiRuntimeProviderEventAdapter(),
    AiCliProvider.copilot: _CopilotJsonRuntimeProviderEventAdapter(),
    AiCliProvider.gemini: _GeminiAiRuntimeProviderEventAdapter(),
    AiCliProvider.acp: _DefaultAiRuntimeProviderEventAdapter(),
  };

  final Map<AiCliProvider, AiRuntimeProviderEventAdapter> _adapters;
  final Map<int, _AiRuntimeParserState> _statesBySessionId =
      <int, _AiRuntimeParserState>{};

  /// Binds this pipeline to an [AiRuntimeEvent] stream.
  Stream<AiTimelineEvent> bind(Stream<AiRuntimeEvent> runtimeEvents) =>
      runtimeEvents.transform(
        StreamTransformer<AiRuntimeEvent, AiTimelineEvent>.fromHandlers(
          handleData: (event, sink) {
            for (final timelineEvent in parse(event)) {
              sink.add(timelineEvent);
            }
          },
          handleError: (error, stackTrace, sink) {
            sink.addError(error, stackTrace);
          },
        ),
      );

  /// Parses one runtime event into zero or more timeline events.
  List<AiTimelineEvent> parse(AiRuntimeEvent runtimeEvent) {
    final state = _statesBySessionId.putIfAbsent(
      runtimeEvent.aiSessionId,
      _AiRuntimeParserState.new,
    );

    switch (runtimeEvent.type) {
      case AiRuntimeEventType.started:
        state
          ..stdoutBuffer = ''
          ..stderrBuffer = '';
        return <AiTimelineEvent>[
          _statusEvent(runtimeEvent, 'Runtime started.'),
        ];
      case AiRuntimeEventType.retried:
        return <AiTimelineEvent>[
          _statusEvent(runtimeEvent, 'Runtime retry requested.'),
        ];
      case AiRuntimeEventType.stdout:
        return _parseChunk(runtimeEvent, state: state, fromStderr: false);
      case AiRuntimeEventType.stderr:
        return _parseChunk(runtimeEvent, state: state, fromStderr: true);
      case AiRuntimeEventType.completed:
        final events = <AiTimelineEvent>[
          ..._flushPending(state: state, runtimeEvent: runtimeEvent),
          _statusEvent(
            runtimeEvent,
            runtimeEvent.exitCode == null
                ? 'Runtime completed.'
                : 'Runtime completed with exit code ${runtimeEvent.exitCode}.',
          ),
        ];
        _statesBySessionId.remove(runtimeEvent.aiSessionId);
        return events;
      case AiRuntimeEventType.cancelled:
        final events = <AiTimelineEvent>[
          ..._flushPending(state: state, runtimeEvent: runtimeEvent),
          _statusEvent(runtimeEvent, 'Runtime cancelled.'),
        ];
        _statesBySessionId.remove(runtimeEvent.aiSessionId);
        return events;
      case AiRuntimeEventType.error:
        final events = <AiTimelineEvent>[
          ..._flushPending(state: state, runtimeEvent: runtimeEvent),
          AiTimelineEvent(
            type: AiTimelineEventType.error,
            aiSessionId: runtimeEvent.aiSessionId,
            connectionId: runtimeEvent.connectionId,
            provider: runtimeEvent.provider,
            message: runtimeEvent.error?.toString() ?? 'Runtime error.',
            metadata: <String, dynamic>{
              'runtimeEventType': runtimeEvent.type.name,
            },
          ),
        ];
        _statesBySessionId.remove(runtimeEvent.aiSessionId);
        return events;
    }
  }

  List<AiTimelineEvent> _parseChunk(
    AiRuntimeEvent runtimeEvent, {
    required _AiRuntimeParserState state,
    required bool fromStderr,
  }) {
    final chunk = runtimeEvent.chunk;
    if (chunk == null || chunk.isEmpty) {
      return const <AiTimelineEvent>[];
    }

    if (!(runtimeEvent.structuredOutput ??
        runtimeEvent.provider.capabilities.supportsStructuredOutput)) {
      return <AiTimelineEvent>[
        _plainTextEvent(runtimeEvent, chunk, fromStderr: fromStderr),
      ];
    }

    final currentBuffer = fromStderr ? state.stderrBuffer : state.stdoutBuffer;
    final combined = '$currentBuffer$chunk';
    final segments = _splitStructuredSegments(combined);
    if (fromStderr) {
      state.stderrBuffer = segments.pending;
    } else {
      state.stdoutBuffer = segments.pending;
    }

    final events = <AiTimelineEvent>[];
    for (final line in segments.completed) {
      events.addAll(
        _parseStructuredLineOrFallback(
          runtimeEvent: runtimeEvent,
          line: line,
          fromStderr: fromStderr,
        ),
      );
    }
    return events;
  }

  List<AiTimelineEvent> _flushPending({
    required _AiRuntimeParserState state,
    required AiRuntimeEvent runtimeEvent,
  }) {
    if (!(runtimeEvent.structuredOutput ??
        runtimeEvent.provider.capabilities.supportsStructuredOutput)) {
      return const <AiTimelineEvent>[];
    }

    final events = <AiTimelineEvent>[];
    if (state.stdoutBuffer.trim().isNotEmpty) {
      events.addAll(
        _parseStructuredLineOrFallback(
          runtimeEvent: runtimeEvent,
          line: state.stdoutBuffer,
          fromStderr: false,
        ),
      );
    }
    if (state.stderrBuffer.trim().isNotEmpty) {
      events.addAll(
        _parseStructuredLineOrFallback(
          runtimeEvent: runtimeEvent,
          line: state.stderrBuffer,
          fromStderr: true,
        ),
      );
    }

    state
      ..stdoutBuffer = ''
      ..stderrBuffer = '';
    return events;
  }

  List<AiTimelineEvent> _parseStructuredLineOrFallback({
    required AiRuntimeEvent runtimeEvent,
    required String line,
    required bool fromStderr,
  }) {
    final trimmedLine = line.trim();
    if (trimmedLine.isEmpty) {
      return const <AiTimelineEvent>[];
    }

    try {
      final decoded = jsonDecode(trimmedLine);
      if (decoded is Map<String, dynamic>) {
        return _adapterFor(
          runtimeEvent.provider,
        ).parseStructuredPayload(payload: decoded, runtimeEvent: runtimeEvent);
      }
      if (decoded is List<Object?>) {
        return decoded
            .whereType<Map<String, dynamic>>()
            .expand(
              (payload) =>
                  _adapterFor(runtimeEvent.provider).parseStructuredPayload(
                    payload: payload,
                    runtimeEvent: runtimeEvent,
                  ),
            )
            .toList(growable: false);
      }
    } on FormatException {
      // Fall back to plain text output below.
    }

    return <AiTimelineEvent>[
      _plainTextEvent(runtimeEvent, trimmedLine, fromStderr: fromStderr),
    ];
  }

  AiTimelineEvent _plainTextEvent(
    AiRuntimeEvent runtimeEvent,
    String text, {
    required bool fromStderr,
  }) => AiTimelineEvent(
    type: fromStderr ? AiTimelineEventType.error : AiTimelineEventType.message,
    aiSessionId: runtimeEvent.aiSessionId,
    connectionId: runtimeEvent.connectionId,
    provider: runtimeEvent.provider,
    message: text,
    metadata: <String, dynamic>{
      'runtimeEventType': runtimeEvent.type.name,
      'structured': false,
    },
  );

  AiTimelineEvent _statusEvent(AiRuntimeEvent runtimeEvent, String message) =>
      AiTimelineEvent(
        type: AiTimelineEventType.status,
        aiSessionId: runtimeEvent.aiSessionId,
        connectionId: runtimeEvent.connectionId,
        provider: runtimeEvent.provider,
        message: message,
        metadata: <String, dynamic>{'runtimeEventType': runtimeEvent.type.name},
      );

  AiRuntimeProviderEventAdapter _adapterFor(AiCliProvider provider) =>
      _adapters[provider] ?? _fallbackAdapter;

  _AiRuntimeStructuredSegments _splitStructuredSegments(String value) {
    final completed = <String>[];
    var current = StringBuffer();
    var inString = false;
    var escaped = false;
    var collectionDepth = 0;

    for (var index = 0; index < value.length; index++) {
      final character = value[index];
      current.write(character);

      if (escaped) {
        escaped = false;
        continue;
      }

      if (inString && character.codeUnitAt(0) == 0x5C) {
        escaped = true;
        continue;
      }

      if (character == '"') {
        inString = !inString;
        continue;
      }

      if (inString) {
        continue;
      }

      if (character == '{' || character == '[') {
        collectionDepth++;
        continue;
      }

      if (character == '}' || character == ']') {
        if (collectionDepth > 0) {
          collectionDepth--;
        }
        if (collectionDepth == 0) {
          final line = current.toString().trim();
          if (line.isNotEmpty) {
            completed.add(line);
          }
          current = StringBuffer();
        }
        continue;
      }

      if (character == '\n' && collectionDepth == 0) {
        final line = current.toString().trim();
        if (line.isNotEmpty) {
          completed.add(line);
        }
        current = StringBuffer();
      }
    }

    return _AiRuntimeStructuredSegments(
      completed: completed,
      pending: current.toString(),
    );
  }
}

class _AiRuntimeParserState {
  String stdoutBuffer = '';
  String stderrBuffer = '';
}

class _AiRuntimeStructuredSegments {
  const _AiRuntimeStructuredSegments({
    required this.completed,
    required this.pending,
  });

  final List<String> completed;
  final String pending;
}

class _DefaultAiRuntimeProviderEventAdapter
    implements AiRuntimeProviderEventAdapter {
  const _DefaultAiRuntimeProviderEventAdapter();

  @override
  List<AiTimelineEvent> parseStructuredPayload({
    required Map<String, dynamic> payload,
    required AiRuntimeEvent runtimeEvent,
  }) {
    final message = _extractMessage(payload) ?? jsonEncode(payload);
    return <AiTimelineEvent>[
      _buildEvent(
        runtimeEvent: runtimeEvent,
        type: _resolveType(payload),
        message: message,
        payload: payload,
      ),
    ];
  }

  AiTimelineEvent _buildEvent({
    required AiRuntimeEvent runtimeEvent,
    required AiTimelineEventType type,
    required String message,
    required Map<String, dynamic> payload,
    Map<String, dynamic> extraMetadata = const <String, dynamic>{},
  }) => AiTimelineEvent(
    type: type,
    aiSessionId: runtimeEvent.aiSessionId,
    connectionId: runtimeEvent.connectionId,
    provider: runtimeEvent.provider,
    message: message,
    metadata: <String, dynamic>{
      'runtimeEventType': runtimeEvent.type.name,
      'structured': true,
      'payload': payload,
      ..._commonSessionMetadata(payload),
      ...extraMetadata,
    },
  );

  AiTimelineEventType _resolveType(Map<String, dynamic> payload) {
    final rawType = _extractFirstString(payload, const <String>[
      'timelineType',
      'eventType',
      'type',
      'kind',
    ]);

    if (rawType != null) {
      final normalizedRawType = rawType.toLowerCase();
      if (normalizedRawType.contains('tool')) {
        return AiTimelineEventType.tool;
      }
      if (normalizedRawType.contains('think') ||
          normalizedRawType.contains('reason')) {
        return AiTimelineEventType.thinking;
      }
      if (normalizedRawType.contains('status') ||
          normalizedRawType.contains('start') ||
          normalizedRawType.contains('complete') ||
          normalizedRawType.contains('cancel')) {
        return AiTimelineEventType.status;
      }
      if (normalizedRawType.contains('error') ||
          normalizedRawType.contains('fail')) {
        return AiTimelineEventType.error;
      }

      return AiTimelineEventType.message;
    }

    final isErrorFlag = payload['is_error'];
    if (isErrorFlag == true) {
      return AiTimelineEventType.error;
    }

    final errorValue = payload['error'];
    if (errorValue != null) {
      return AiTimelineEventType.error;
    }
    return AiTimelineEventType.message;
  }

  String? _extractMessage(Map<String, dynamic> payload) {
    for (final key in const <String>[
      'message',
      'content',
      'text',
      'status',
      'thinking',
      'reasoning',
      'error',
    ]) {
      final resolved = _stringFromValue(payload[key]);
      if (resolved != null) {
        return resolved;
      }
    }
    return null;
  }

  String? _extractFirstString(Map<String, dynamic> payload, List<String> keys) {
    for (final key in keys) {
      final value = payload[key];
      if (value is String && value.trim().isNotEmpty) {
        return value;
      }
    }
    return null;
  }

  String? _stringFromValue(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is String) {
      final trimmedValue = value.trim();
      return trimmedValue.isEmpty ? null : trimmedValue;
    }
    if (value is num || value is bool) {
      return value.toString();
    }
    if (value is List<Object?>) {
      final parts = value
          .map(_stringFromValue)
          .whereType<String>()
          .where((part) => part.trim().isNotEmpty)
          .toList(growable: false);
      if (parts.isEmpty) {
        return null;
      }
      return parts.join('\n');
    }
    if (value is Map<String, dynamic>) {
      for (final key in const <String>['text', 'content', 'message', 'value']) {
        final nested = _stringFromValue(value[key]);
        if (nested != null) {
          return nested;
        }
      }
    }
    return null;
  }

  Map<String, dynamic>? _mapFromValue(Object? value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map<Object?, Object?>) {
      return value.map((key, mapValue) => MapEntry(key.toString(), mapValue));
    }
    return null;
  }

  Map<String, dynamic> _commonSessionMetadata(Map<String, dynamic> payload) {
    final metadata = <String, dynamic>{};
    final providerSessionId = _extractFirstString(payload, const <String>[
      'session_id',
      'sessionId',
      'sessionID',
      'thread_id',
      'threadId',
    ]);
    if (providerSessionId != null) {
      metadata['providerSessionId'] = providerSessionId;
    }
    final currentModelId = _extractFirstString(payload, const <String>[
      'model',
      'currentModelId',
      'modelId',
    ]);
    if (currentModelId != null) {
      metadata['currentModelId'] = currentModelId;
    }
    final currentModeId = _extractFirstString(payload, const <String>[
      'currentModeId',
      'modeId',
      'approvalMode',
    ]);
    if (currentModeId != null) {
      metadata['currentModeId'] = currentModeId;
    }
    return metadata;
  }
}

class _ClaudeAiRuntimeProviderEventAdapter
    extends _DefaultAiRuntimeProviderEventAdapter {
  const _ClaudeAiRuntimeProviderEventAdapter();

  @override
  List<AiTimelineEvent> parseStructuredPayload({
    required Map<String, dynamic> payload,
    required AiRuntimeEvent runtimeEvent,
  }) {
    final type = payload['type']?.toString();
    if (type == 'system') {
      final subtype = payload['subtype']?.toString();
      if (subtype == 'init') {
        final model = payload['model']?.toString();
        final message = model == null || model.trim().isEmpty
            ? 'Claude session initialized.'
            : 'Claude session initialized · model: $model';
        return <AiTimelineEvent>[
          _buildEvent(
            runtimeEvent: runtimeEvent,
            type: AiTimelineEventType.status,
            message: message,
            payload: payload,
            extraMetadata: <String, dynamic>{
              if (payload['session_id'] != null)
                'providerSessionId': payload['session_id'],
              if (payload['model'] != null) 'currentModelId': payload['model'],
              if (payload['slash_commands'] != null)
                'availableSlashCommands': payload['slash_commands'],
            },
          ),
        ];
      }
    }
    if (type == 'result') {
      final stopReason = payload['stop_reason']?.toString();
      final message = stopReason == null || stopReason.trim().isEmpty
          ? 'Claude turn completed.'
          : 'Claude turn completed · $stopReason';
      return <AiTimelineEvent>[
        _buildEvent(
          runtimeEvent: runtimeEvent,
          type: AiTimelineEventType.status,
          message: message,
          payload: payload,
          extraMetadata: <String, dynamic>{
            'turnLifecycle': 'completed',
            if (payload['session_id'] != null)
              'providerSessionId': payload['session_id'],
          },
        ),
      ];
    }
    final normalizedPayload = <String, dynamic>{...payload};
    final message = _extractClaudeMessage(payload);
    if (message != null) {
      normalizedPayload['content'] = message;
    }
    return super.parseStructuredPayload(
      payload: normalizedPayload,
      runtimeEvent: runtimeEvent,
    );
  }

  String? _extractClaudeMessage(Map<String, dynamic> payload) {
    final messagePayload = payload['message'];
    if (messagePayload is Map<String, dynamic>) {
      final content = messagePayload['content'];
      if (content is List<Object?>) {
        final parts = content
            .whereType<Map<String, dynamic>>()
            .map((entry) {
              final text = entry['text'];
              if (text is String && text.isNotEmpty) {
                return text;
              }
              return null;
            })
            .whereType<String>()
            .toList(growable: false);
        if (parts.isNotEmpty) {
          return parts.join('\n');
        }
      }
    }

    final delta = payload['delta'];
    if (delta is Map<String, dynamic>) {
      final text = delta['text'];
      if (text is String && text.isNotEmpty) {
        return text;
      }
    }

    return null;
  }
}

class _CodexAiRuntimeProviderEventAdapter
    extends _DefaultAiRuntimeProviderEventAdapter {
  const _CodexAiRuntimeProviderEventAdapter();

  @override
  List<AiTimelineEvent> parseStructuredPayload({
    required Map<String, dynamic> payload,
    required AiRuntimeEvent runtimeEvent,
  }) {
    final type = payload['type']?.toString();
    switch (type) {
      case 'thread.started':
        return <AiTimelineEvent>[
          _buildEvent(
            runtimeEvent: runtimeEvent,
            type: AiTimelineEventType.status,
            message: 'Codex session started.',
            payload: payload,
            extraMetadata: <String, dynamic>{
              if (payload['thread_id'] != null)
                'providerSessionId': payload['thread_id'],
            },
          ),
        ];
      case 'turn.started':
        return <AiTimelineEvent>[
          _buildEvent(
            runtimeEvent: runtimeEvent,
            type: AiTimelineEventType.status,
            message: 'Codex turn started.',
            payload: payload,
          ),
        ];
      case 'turn.completed':
        return <AiTimelineEvent>[
          _buildEvent(
            runtimeEvent: runtimeEvent,
            type: AiTimelineEventType.status,
            message: 'Codex turn completed.',
            payload: payload,
            extraMetadata: const <String, dynamic>{
              'turnLifecycle': 'completed',
            },
          ),
        ];
      case 'item.completed':
        final item = payload['item'];
        if (item is! Map<String, dynamic>) {
          break;
        }
        final itemType = item['type']?.toString() ?? '';
        final message =
            item['text']?.toString() ??
            item['content']?.toString() ??
            jsonEncode(item);
        if (message.trim().isEmpty) {
          return const <AiTimelineEvent>[];
        }
        final timelineType = itemType.contains('tool')
            ? AiTimelineEventType.tool
            : itemType.contains('reason') || itemType.contains('think')
            ? AiTimelineEventType.thinking
            : AiTimelineEventType.message;
        return <AiTimelineEvent>[
          _buildEvent(
            runtimeEvent: runtimeEvent,
            type: timelineType,
            message: message,
            payload: payload,
          ),
        ];
    }
    return super.parseStructuredPayload(
      payload: payload,
      runtimeEvent: runtimeEvent,
    );
  }
}

class _GeminiAiRuntimeProviderEventAdapter
    extends _DefaultAiRuntimeProviderEventAdapter {
  const _GeminiAiRuntimeProviderEventAdapter();

  @override
  List<AiTimelineEvent> parseStructuredPayload({
    required Map<String, dynamic> payload,
    required AiRuntimeEvent runtimeEvent,
  }) {
    final type = payload['type']?.toString();
    switch (type) {
      case 'init':
        final model = payload['model']?.toString();
        final message = model == null || model.trim().isEmpty
            ? 'Gemini session initialized.'
            : 'Gemini session initialized · model: $model';
        return <AiTimelineEvent>[
          _buildEvent(
            runtimeEvent: runtimeEvent,
            type: AiTimelineEventType.status,
            message: message,
            payload: payload,
            extraMetadata: <String, dynamic>{
              if (payload['session_id'] != null)
                'providerSessionId': payload['session_id'],
              if (payload['model'] != null) 'currentModelId': payload['model'],
            },
          ),
        ];
      case 'message':
        final role = payload['role']?.toString();
        if (role == 'user') {
          return const <AiTimelineEvent>[];
        }
        final content = payload['content']?.toString();
        if (content == null || content.trim().isEmpty) {
          return const <AiTimelineEvent>[];
        }
        return <AiTimelineEvent>[
          _buildEvent(
            runtimeEvent: runtimeEvent,
            type: role == 'assistant'
                ? AiTimelineEventType.message
                : AiTimelineEventType.status,
            message: content,
            payload: payload,
            extraMetadata: <String, dynamic>{
              if (payload['session_id'] != null)
                'providerSessionId': payload['session_id'],
            },
          ),
        ];
      case 'result':
        final status = payload['status']?.toString();
        final message = status == null || status.trim().isEmpty
            ? 'Gemini turn completed.'
            : 'Gemini turn completed · $status';
        return <AiTimelineEvent>[
          _buildEvent(
            runtimeEvent: runtimeEvent,
            type: AiTimelineEventType.status,
            message: message,
            payload: payload,
            extraMetadata: const <String, dynamic>{
              'turnLifecycle': 'completed',
            },
          ),
        ];
    }
    return super.parseStructuredPayload(
      payload: payload,
      runtimeEvent: runtimeEvent,
    );
  }
}

class _CopilotJsonRuntimeProviderEventAdapter
    extends _DefaultAiRuntimeProviderEventAdapter {
  const _CopilotJsonRuntimeProviderEventAdapter();

  @override
  List<AiTimelineEvent> parseStructuredPayload({
    required Map<String, dynamic> payload,
    required AiRuntimeEvent runtimeEvent,
  }) {
    final type = payload['type']?.toString();
    final data = payload['data'];
    switch (type) {
      case 'session.tools_updated':
        if (data is! Map<String, dynamic>) {
          break;
        }
        final model = data['model']?.toString();
        final message = model == null || model.trim().isEmpty
            ? 'Copilot session initialized.'
            : 'Copilot session initialized · model: $model';
        return <AiTimelineEvent>[
          _buildEvent(
            runtimeEvent: runtimeEvent,
            type: AiTimelineEventType.status,
            message: message,
            payload: payload,
            extraMetadata: <String, dynamic>{
              if (model != null && model.trim().isNotEmpty)
                'currentModelId': model,
            },
          ),
        ];
      case 'assistant.message_delta':
      case 'user.message':
        return const <AiTimelineEvent>[];
      case 'assistant.message':
        if (data is! Map<String, dynamic>) {
          break;
        }
        final content = data['content']?.toString();
        if (content == null || content.trim().isEmpty) {
          return const <AiTimelineEvent>[];
        }
        return <AiTimelineEvent>[
          _buildEvent(
            runtimeEvent: runtimeEvent,
            type: AiTimelineEventType.message,
            message: content,
            payload: payload,
            extraMetadata: <String, dynamic>{
              if (data['reasoningOpaque'] != null)
                'reasoningOpaque': data['reasoningOpaque'],
              if (data['toolRequests'] != null)
                'toolRequests': data['toolRequests'],
            },
          ),
        ];
      case 'tool.execution_start':
        if (data is! Map<String, dynamic>) {
          break;
        }
        final toolName = data['toolName']?.toString();
        if (toolName == null || toolName.trim().isEmpty) {
          return const <AiTimelineEvent>[];
        }
        return <AiTimelineEvent>[
          _buildEvent(
            runtimeEvent: runtimeEvent,
            type: AiTimelineEventType.tool,
            message: 'Running $toolName',
            payload: payload,
            extraMetadata: <String, dynamic>{
              'toolName': toolName,
              'toolStatus': 'started',
              if (data['toolCallId'] != null) 'toolCallId': data['toolCallId'],
              if (data['arguments'] != null) 'input': data['arguments'],
            },
          ),
        ];
      case 'tool.execution_complete':
        if (data is! Map<String, dynamic>) {
          break;
        }
        final toolName = data['toolName']?.toString();
        if (toolName == null || toolName.trim().isEmpty) {
          return const <AiTimelineEvent>[];
        }
        final result = _mapFromValue(data['result']);
        final status = data['success'] == false ? 'failed' : 'completed';
        final message = result?['content']?.toString().trim();
        return <AiTimelineEvent>[
          _buildEvent(
            runtimeEvent: runtimeEvent,
            type: AiTimelineEventType.tool,
            message: message?.isNotEmpty ?? false
                ? message!
                : '$toolName $status.',
            payload: payload,
            extraMetadata: <String, dynamic>{
              'toolName': toolName,
              'toolStatus': status,
              if (data['toolCallId'] != null) 'toolCallId': data['toolCallId'],
              ...?result == null ? null : <String, dynamic>{'output': result},
            },
          ),
        ];
      case 'result':
        final sessionId = payload['sessionId']?.toString();
        final message = payload['exitCode'] == 0
            ? 'Copilot turn completed.'
            : 'Copilot turn completed with exit code ${payload['exitCode']}.';
        return <AiTimelineEvent>[
          _buildEvent(
            runtimeEvent: runtimeEvent,
            type: AiTimelineEventType.status,
            message: message,
            payload: payload,
            extraMetadata: <String, dynamic>{
              'turnLifecycle': 'completed',
              ...?sessionId == null
                  ? null
                  : <String, dynamic>{'providerSessionId': sessionId},
            },
          ),
        ];
    }
    return super.parseStructuredPayload(
      payload: payload,
      runtimeEvent: runtimeEvent,
    );
  }
}

class _OpenCodeAiRuntimeProviderEventAdapter
    extends _DefaultAiRuntimeProviderEventAdapter {
  const _OpenCodeAiRuntimeProviderEventAdapter();

  @override
  List<AiTimelineEvent> parseStructuredPayload({
    required Map<String, dynamic> payload,
    required AiRuntimeEvent runtimeEvent,
  }) {
    final type = payload['type']?.toString();
    switch (type) {
      case 'text':
        final part = payload['part'];
        if (part is! Map<String, dynamic>) {
          break;
        }
        final text = part['text']?.toString();
        if (text == null || text.trim().isEmpty) {
          return const <AiTimelineEvent>[];
        }
        return <AiTimelineEvent>[
          _buildEvent(
            runtimeEvent: runtimeEvent,
            type: AiTimelineEventType.message,
            message: text,
            payload: payload,
            extraMetadata: <String, dynamic>{
              if (payload['sessionID'] != null)
                'providerSessionId': payload['sessionID'],
            },
          ),
        ];
      case 'step_start':
        return <AiTimelineEvent>[
          _buildEvent(
            runtimeEvent: runtimeEvent,
            type: AiTimelineEventType.status,
            message: 'OpenCode step started.',
            payload: payload,
            extraMetadata: <String, dynamic>{
              if (payload['sessionID'] != null)
                'providerSessionId': payload['sessionID'],
            },
          ),
        ];
      case 'step_finish':
        final part = payload['part'];
        final reason = part is Map<String, dynamic>
            ? part['reason']?.toString()
            : null;
        final message = reason == null || reason.trim().isEmpty
            ? 'OpenCode step completed.'
            : 'OpenCode step completed · $reason';
        return <AiTimelineEvent>[
          _buildEvent(
            runtimeEvent: runtimeEvent,
            type: AiTimelineEventType.status,
            message: message,
            payload: payload,
            extraMetadata: <String, dynamic>{
              'turnLifecycle': 'completed',
              if (payload['sessionID'] != null)
                'providerSessionId': payload['sessionID'],
            },
          ),
        ];
    }
    return super.parseStructuredPayload(
      payload: payload,
      runtimeEvent: runtimeEvent,
    );
  }
}

/// Provider for [AiRuntimeEventParserPipeline].
final aiRuntimeEventParserPipelineProvider =
    Provider<AiRuntimeEventParserPipeline>(
      (ref) => AiRuntimeEventParserPipeline(),
    );

/// Stream of normalized timeline events from [AiRuntimeService].
final aiRuntimeTimelineEventsProvider =
    StreamProvider.autoDispose<AiTimelineEvent>((ref) {
      final runtimeService = ref.watch(aiRuntimeServiceProvider);
      final parserPipeline = ref.watch(aiRuntimeEventParserPipelineProvider);
      return parserPipeline.bind(runtimeService.events);
    });
