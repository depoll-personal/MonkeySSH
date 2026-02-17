// ignore_for_file: public_member_api_docs

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:monkeyssh/domain/models/ai_cli_provider.dart';
import 'package:monkeyssh/domain/services/ai_runtime_event_parser_pipeline.dart';
import 'package:monkeyssh/domain/services/ai_runtime_service.dart';

void main() {
  group('AiRuntimeEventParserPipeline', () {
    test('parses structured JSON lines and buffered fragments', () {
      final pipeline = AiRuntimeEventParserPipeline();

      final firstOutput = pipeline.parse(
        _runtimeEvent(
          type: AiRuntimeEventType.stdout,
          provider: AiCliProvider.claude,
          chunk:
              '{"type":"thinking","content":"Planning"}\n'
              '{"type":"tool_use","content":"running ls"',
        ),
      );
      final secondOutput = pipeline.parse(
        _runtimeEvent(
          type: AiRuntimeEventType.stdout,
          provider: AiCliProvider.claude,
          chunk: '}\n',
        ),
      );

      expect(firstOutput, hasLength(1));
      expect(firstOutput.single.type, AiTimelineEventType.thinking);
      expect(firstOutput.single.message, 'Planning');

      expect(secondOutput, hasLength(1));
      expect(secondOutput.single.type, AiTimelineEventType.tool);
      expect(secondOutput.single.message, 'running ls');
    });

    test('falls back to plain text for unsupported structured chunks', () {
      final pipeline = AiRuntimeEventParserPipeline();

      final stdoutEvents = pipeline.parse(
        _runtimeEvent(
          type: AiRuntimeEventType.stdout,
          provider: AiCliProvider.claude,
          chunk: 'plain stdout line\n',
        ),
      );
      final stderrEvents = pipeline.parse(
        _runtimeEvent(
          type: AiRuntimeEventType.stderr,
          provider: AiCliProvider.copilot,
          chunk: 'plain stderr line',
        ),
      );

      expect(stdoutEvents.single.type, AiTimelineEventType.message);
      expect(stdoutEvents.single.message, 'plain stdout line');
      expect(stderrEvents.single.type, AiTimelineEventType.error);
      expect(stderrEvents.single.message, 'plain stderr line');
    });

    test('bind integrates runtime event stream into timeline stream', () async {
      final pipeline = AiRuntimeEventParserPipeline();
      final controller = StreamController<AiRuntimeEvent>();

      final timelineEvents = <AiTimelineEvent>[];
      final subscription = pipeline
          .bind(controller.stream)
          .listen(timelineEvents.add);

      controller
        ..add(
          _runtimeEvent(
            type: AiRuntimeEventType.started,
            provider: AiCliProvider.codex,
          ),
        )
        ..add(
          _runtimeEvent(
            type: AiRuntimeEventType.stdout,
            provider: AiCliProvider.codex,
            chunk: '{"type":"message","content":"Hello"}\n',
          ),
        )
        ..add(
          _runtimeEvent(
            type: AiRuntimeEventType.completed,
            provider: AiCliProvider.codex,
            exitCode: 0,
          ),
        );

      await controller.close();
      await Future<void>.delayed(Duration.zero);
      await subscription.cancel();

      expect(timelineEvents.map((event) => event.type), <AiTimelineEventType>[
        AiTimelineEventType.status,
        AiTimelineEventType.message,
        AiTimelineEventType.status,
      ]);
    });
  });
}

AiRuntimeEvent _runtimeEvent({
  required AiRuntimeEventType type,
  required AiCliProvider provider,
  String? chunk,
  int? exitCode,
}) => AiRuntimeEvent(
  type: type,
  aiSessionId: 7,
  connectionId: 42,
  provider: provider,
  chunk: chunk,
  exitCode: exitCode,
);
