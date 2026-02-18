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

    testWidgets('requires ACP client command when ACP provider is selected', (
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
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('ai-provider-field')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('acp-client').last);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('ai-acp-client-command-field')),
        findsOneWidget,
      );

      await tester.tap(find.text('Start Session'));
      await tester.pump();

      expect(find.text('ACP client command is required.'), findsOneWidget);
    });
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
          message: 'Hello',
          createdAt: DateTime(2024),
        ),
        AiTimelineEntry(
          id: 3,
          sessionId: 9,
          role: 'assistant',
          message: 'Hi there',
          createdAt: DateTime(2024),
        ),
        AiTimelineEntry(
          id: 4,
          sessionId: 9,
          role: 'tool',
          message: 'Running ls',
          metadata: '{"code":0}',
          createdAt: DateTime(2024),
        ),
        AiTimelineEntry(
          id: 5,
          sessionId: 9,
          role: 'thinking',
          message: 'Planning response',
          createdAt: DateTime(2024),
        ),
        AiTimelineEntry(
          id: 6,
          sessionId: 9,
          role: 'error',
          message: 'Command failed',
          metadata: '{"code":1}',
          createdAt: DateTime(2024),
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: entries
                  .map((entry) => AiTimelineEntryTile(entry: entry))
                  .toList(growable: false),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Runtime started.'), findsOneWidget);
      expect(find.text('Hello'), findsOneWidget);
      expect(find.text('Hi there'), findsOneWidget);
      expect(find.text('Running ls'), findsOneWidget);
      expect(find.text('Planning response'), findsOneWidget);
      expect(find.text('Command failed'), findsOneWidget);
      expect(find.byIcon(Icons.build_circle_outlined), findsOneWidget);
      expect(find.byIcon(Icons.psychology_alt_outlined), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
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
