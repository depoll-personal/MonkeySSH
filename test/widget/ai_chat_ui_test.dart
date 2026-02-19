// ignore_for_file: public_member_api_docs

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:monkeyssh/data/database/database.dart';
import 'package:monkeyssh/domain/models/ai_cli_provider.dart';
import 'package:monkeyssh/presentation/screens/ai_chat_session_screen.dart'
    show AiChatSessionScreen, AiTimelineEntryTile;
import 'package:monkeyssh/presentation/screens/ai_start_session_screen.dart';

void main() {
  group('AI start flow', () {
    testWidgets('shows empty-host guidance', (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: const MaterialApp(home: AiStartSessionScreen()),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('AI Chat'), findsNWidgets(2));
      expect(find.text('Host'), findsOneWidget);
      expect(find.text('Working directory'), findsOneWidget);
      expect(find.text('AI provider'), findsOneWidget);
      expect(find.text('Add a host first to start AI chat.'), findsOneWidget);
    });

    testWidgets('validates working directory before session start', (
      tester,
    ) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);

      await db
          .into(db.hosts)
          .insert(
            HostsCompanion.insert(
              label: 'Prod',
              hostname: 'prod.example.com',
              username: 'ubuntu',
            ),
          );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: const MaterialApp(home: AiStartSessionScreen()),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      await tester.enterText(
        find.byKey(const Key('ai-working-directory-field')),
        '',
      );
      await tester.tap(find.text('Start Session'));
      await tester.pump();

      expect(find.text('Working directory is required.'), findsOneWidget);
    });

    testWidgets(
      'requires ACP client command when custom ACP mode is selected',
      (tester) async {
        final db = AppDatabase.forTesting(NativeDatabase.memory());
        addTearDown(db.close);

        await db
            .into(db.hosts)
            .insert(
              HostsCompanion.insert(
                label: 'Prod',
                hostname: 'prod.example.com',
                username: 'ubuntu',
              ),
            );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [databaseProvider.overrideWithValue(db)],
            child: const MaterialApp(home: AiStartSessionScreen()),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('ai-provider-field')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('acp-client').last);
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('ai-acp-client-preset-field')),
          findsOneWidget,
        );
        expect(find.textContaining('Command: '), findsOneWidget);

        await tester.tap(find.byKey(const Key('ai-acp-client-preset-field')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Custom command').last);
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('ai-acp-client-command-field')),
          findsOneWidget,
        );

        await tester.tap(find.text('Start Session'));
        await tester.pump();

        expect(find.text('ACP client command is required.'), findsOneWidget);
      },
    );
  });

  group('AI timeline rendering', () {
    testWidgets('renders timeline entry variants', (tester) async {
      final entries = <AiTimelineEntry>[
        AiTimelineEntry(
          id: 1,
          sessionId: 9,
          role: 'status',
          message: 'Runtime started.',
          createdAt: DateTime(2024),
        ),
        AiTimelineEntry(
          id: 2,
          sessionId: 9,
          role: 'user',
          message: 'Hello **team**',
          createdAt: DateTime(2024),
        ),
        AiTimelineEntry(
          id: 3,
          sessionId: 9,
          role: 'assistant',
          message: 'Hi there\n\n- Step 1\n- Step 2',
          createdAt: DateTime(2024),
        ),
        AiTimelineEntry(
          id: 4,
          sessionId: 9,
          role: 'tool',
          message: 'Running `ls`',
          metadata:
              '{"payload":{"toolName":"code-reviewer","subagent":"code-reviewer","input":"Review changed files","output":"No critical issues"}}',
          createdAt: DateTime(2024),
        ),
        AiTimelineEntry(
          id: 5,
          sessionId: 9,
          role: 'thinking',
          message: 'Planning response with **reasoning**.',
          createdAt: DateTime(2024),
        ),
        AiTimelineEntry(
          id: 6,
          sessionId: 9,
          role: 'error',
          message: '\u001B[31mCommand failed\u001B[0m with `exit 1`.',
          metadata: '{"code":1}',
          createdAt: DateTime(2024),
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: entries
                    .map((entry) => AiTimelineEntryTile(entry: entry))
                    .toList(growable: false),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Runtime started.'), findsOneWidget);
      expect(find.textContaining('Hello'), findsOneWidget);
      expect(find.textContaining('Hi there'), findsOneWidget);
      expect(find.textContaining('Running'), findsOneWidget);
      expect(find.textContaining('Planning response'), findsOneWidget);
      expect(find.textContaining('Command failed'), findsOneWidget);
      expect(find.textContaining('\u001B[31m'), findsNothing);
      expect(find.text('Prompt'), findsOneWidget);
      expect(find.text('Assistant'), findsOneWidget);
      expect(find.text('Subagent call'), findsOneWidget);
      expect(find.text('Model thinking'), findsOneWidget);
      expect(find.text('Runtime error'), findsOneWidget);
      expect(find.text('Input'), findsOneWidget);
      expect(find.text('Output'), findsOneWidget);
      expect(find.byIcon(Icons.psychology_alt_outlined), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets('renders ANSI/control-heavy timeline output safely', (
      tester,
    ) async {
      final entries = <AiTimelineEntry>[
        AiTimelineEntry(
          id: 1,
          sessionId: 10,
          role: 'error',
          message:
              '\u001B[31mRuntime failed\u001B[0m\r\n\u001B]8;;https://example.com\u0007link\u001B]8;;\u0007',
          createdAt: DateTime(2024),
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: entries
                    .map((entry) => AiTimelineEntryTile(entry: entry))
                    .toList(growable: false),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.textContaining('Runtime failed'), findsOneWidget);
      expect(find.textContaining('\u001B[31m'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('collapses completed tool cards and shows called tool', (
      tester,
    ) async {
      final entries = <AiTimelineEntry>[
        AiTimelineEntry(
          id: 9,
          sessionId: 12,
          role: 'tool',
          message: 'Viewing /Users/depoll/Code',
          metadata:
              r'{"toolKind":"view","toolStatus":"completed","input":"{\"path\":\"/Users/depoll/Code\"}"}',
          createdAt: DateTime(2024),
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: entries
                    .map((entry) => AiTimelineEntryTile(entry: entry))
                    .toList(growable: false),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Tool: view · completed'), findsOneWidget);
      expect(find.text('Input'), findsNothing);

      await tester.tap(find.text('Tool call'));
      await tester.pumpAndSettle();

      expect(find.text('Input'), findsOneWidget);
    });

    testWidgets('sanitizes status entries with terminal control sequences', (
      tester,
    ) async {
      final entries = <AiTimelineEntry>[
        AiTimelineEntry(
          id: 1,
          sessionId: 11,
          role: 'status',
          message: '\u001B[32mRuntime started\u001B[0m\u0007',
          createdAt: DateTime(2024),
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: entries
                    .map((entry) => AiTimelineEntryTile(entry: entry))
                    .toList(growable: false),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.textContaining('Runtime started'), findsOneWidget);
      expect(find.textContaining('\u001B[32m'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('AI session resume', () {
    testWidgets('restores saved metadata when reopening a session', (
      tester,
    ) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);

      final workspaceId = await db
          .into(db.aiWorkspaces)
          .insert(
            AiWorkspacesCompanion.insert(name: 'Workspace', path: '/workspace'),
          );
      final sessionId = await db
          .into(db.aiSessions)
          .insert(
            AiSessionsCompanion.insert(
              workspaceId: workspaceId,
              title: 'Resume me',
            ),
          );
      await db
          .into(db.aiTimelineEntries)
          .insert(
            AiTimelineEntriesCompanion.insert(
              sessionId: sessionId,
              role: 'status',
              message: 'Saved metadata',
              metadata: const Value(
                '{"provider":"codex","workingDirectory":"/repo","connectionId":55,"hostId":7}',
              ),
            ),
          );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: MaterialApp(
            home: AiChatSessionScreen(
              sessionId: sessionId,
              autoStartRuntime: false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('codex · /repo'), findsOneWidget);
      expect(find.textContaining('Model: default'), findsOneWidget);
      expect(find.textContaining('Context: ~'), findsOneWidget);
      expect(find.textContaining('Mode: one-shot'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('shows detached state and reconnect control on fallback', (
      tester,
    ) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);

      final workspaceId = await db
          .into(db.aiWorkspaces)
          .insert(
            AiWorkspacesCompanion.insert(name: 'Workspace', path: '/workspace'),
          );
      final sessionId = await db
          .into(db.aiSessions)
          .insert(
            AiSessionsCompanion.insert(
              workspaceId: workspaceId,
              title: 'Fallback',
            ),
          );
      await db
          .into(db.aiTimelineEntries)
          .insert(
            AiTimelineEntriesCompanion.insert(
              sessionId: sessionId,
              role: 'status',
              message: 'Saved metadata',
              metadata: const Value(
                '{"provider":"claude","workingDirectory":"/repo","connectionId":999,"hostId":3}',
              ),
            ),
          );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: MaterialApp(home: AiChatSessionScreen(sessionId: sessionId)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Detached'), findsOneWidget);
      expect(
        find.byKey(const Key('ai-reconnect-runtime-button')),
        findsOneWidget,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('shows ACP executable override from saved metadata', (
      tester,
    ) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);

      final workspaceId = await db
          .into(db.aiWorkspaces)
          .insert(
            AiWorkspacesCompanion.insert(name: 'Workspace', path: '/workspace'),
          );
      final sessionId = await db
          .into(db.aiSessions)
          .insert(
            AiSessionsCompanion.insert(
              workspaceId: workspaceId,
              title: 'ACP resume',
            ),
          );
      await db
          .into(db.aiTimelineEntries)
          .insert(
            AiTimelineEntriesCompanion.insert(
              sessionId: sessionId,
              role: 'status',
              message: 'Saved metadata',
              metadata: const Value(
                '{"provider":"acp","workingDirectory":"/repo","executableOverride":"my-acp-client --stdio"}',
              ),
            ),
          );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: MaterialApp(
            home: AiChatSessionScreen(
              sessionId: sessionId,
              autoStartRuntime: false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('my-acp-client --stdio · /repo'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  });

  group('AI chat composer autocomplete', () {
    testWidgets('shows slash commands after runtime error timeline entries', (
      tester,
    ) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final workspaceId = await db
          .into(db.aiWorkspaces)
          .insert(
            AiWorkspacesCompanion.insert(name: 'Workspace', path: '/workspace'),
          );
      final sessionId = await db
          .into(db.aiSessions)
          .insert(
            AiSessionsCompanion.insert(
              workspaceId: workspaceId,
              title: 'Autocomplete after errors',
            ),
          );
      await db
          .into(db.aiTimelineEntries)
          .insert(
            AiTimelineEntriesCompanion.insert(
              sessionId: sessionId,
              role: 'error',
              message: '\u001B[31mRuntime failed\u001B[0m',
            ),
          );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: MaterialApp(
            home: AiChatSessionScreen(
              sessionId: sessionId,
              connectionId: 9,
              provider: AiCliProvider.claude,
              remoteWorkingDirectory: '/workspace',
              autoStartRuntime: false,
              remoteFileSuggestionLoader: () async => const <String>[],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('ai-chat-input')));
      await tester.enterText(find.byKey(const Key('ai-chat-input')), '/');
      await tester.pumpAndSettle();

      expect(find.text('/model'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('shows provider slash commands and applies with keyboard', (
      tester,
    ) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final workspaceId = await db
          .into(db.aiWorkspaces)
          .insert(
            AiWorkspacesCompanion.insert(name: 'Workspace', path: '/workspace'),
          );
      final sessionId = await db
          .into(db.aiSessions)
          .insert(
            AiSessionsCompanion.insert(
              workspaceId: workspaceId,
              title: 'Autocomplete',
            ),
          );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: MaterialApp(
            home: AiChatSessionScreen(
              sessionId: sessionId,
              connectionId: 9,
              provider: AiCliProvider.claude,
              remoteWorkingDirectory: '/workspace',
              autoStartRuntime: false,
              remoteFileSuggestionLoader: () async => const <String>[],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('ai-chat-input')));
      await tester.enterText(find.byKey(const Key('ai-chat-input')), '/mo');
      await tester.pumpAndSettle();

      expect(find.text('/model'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      final textField = tester.widget<TextField>(
        find.byKey(const Key('ai-chat-input')),
      );
      expect(textField.controller?.text, '/model ');

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('shows remote file suggestions and applies with touch', (
      tester,
    ) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final workspaceId = await db
          .into(db.aiWorkspaces)
          .insert(
            AiWorkspacesCompanion.insert(name: 'Workspace', path: '/workspace'),
          );
      final sessionId = await db
          .into(db.aiSessions)
          .insert(
            AiSessionsCompanion.insert(
              workspaceId: workspaceId,
              title: 'Autocomplete',
            ),
          );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: MaterialApp(
            home: AiChatSessionScreen(
              sessionId: sessionId,
              connectionId: 9,
              provider: AiCliProvider.copilot,
              remoteWorkingDirectory: '/workspace',
              autoStartRuntime: false,
              remoteFileSuggestionLoader: () async => const <String>[
                'README.md',
                'lib/main.dart',
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('ai-chat-input')));
      await tester.enterText(
        find.byKey(const Key('ai-chat-input')),
        'open @rea',
      );
      await tester.pumpAndSettle();

      expect(find.text('@README.md'), findsOneWidget);
      await tester.tap(find.text('@README.md'));
      await tester.pumpAndSettle();

      final textField = tester.widget<TextField>(
        find.byKey(const Key('ai-chat-input')),
      );
      expect(textField.controller?.text, 'open @README.md ');

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  });
}
