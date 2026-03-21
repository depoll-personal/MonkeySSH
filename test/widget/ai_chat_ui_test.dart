// ignore_for_file: public_member_api_docs

import 'dart:convert';

import 'package:drift/drift.dart' show OrderingTerm, Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:monkeyssh/data/database/database.dart';
import 'package:monkeyssh/domain/models/ai_cli_provider.dart';
import 'package:monkeyssh/domain/services/ssh_service.dart';
import 'package:monkeyssh/presentation/screens/ai_chat_session_screen.dart'
    show AiChatSessionScreen, AiTimelineEntryTile;
import 'package:monkeyssh/presentation/screens/ai_start_session_screen.dart';

void main() {
  Future<void> disposePumpedWidgetTree(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  }

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
      await disposePumpedWidgetTree(tester);
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
      await disposePumpedWidgetTree(tester);
    });

    testWidgets('renders long host labels without overflow on narrow screens', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 640);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);

      await db
          .into(db.hosts)
          .insert(
            HostsCompanion.insert(
              label: 'UX Host With A Very Long Friendly Label',
              hostname: 'very-long-hostname-for-mobile-layout.example.internal',
              username: 'mobile-user',
            ),
          );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: const MaterialApp(home: AiStartSessionScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('ai-host-field')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await disposePumpedWidgetTree(tester);
    });

    testWidgets(
      'does not overwrite a manual provider selection during restore',
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
        final workspaceId = await db
            .into(db.aiWorkspaces)
            .insert(
              AiWorkspacesCompanion.insert(
                name: 'Workspace',
                path: '/tmp/workspace',
              ),
            );
        final sessionId = await db
            .into(db.aiSessions)
            .insert(
              AiSessionsCompanion.insert(
                workspaceId: workspaceId,
                title: 'Previous ACP session',
              ),
            );
        await db
            .into(db.aiTimelineEntries)
            .insert(
              AiTimelineEntriesCompanion.insert(
                sessionId: sessionId,
                role: 'status',
                message: 'Connected',
                metadata: Value(
                  jsonEncode(<String, dynamic>{
                    'provider': AiCliProvider.acp.name,
                    'acpClientId': 'claude-code',
                  }),
                ),
              ),
            );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [databaseProvider.overrideWithValue(db)],
            child: const MaterialApp(home: AiStartSessionScreen()),
          ),
        );
        await tester.pump();

        await tester.tap(find.byKey(const Key('ai-provider-field')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('copilot').last);
        await tester.pumpAndSettle();

        expect(find.text('copilot'), findsOneWidget);
        expect(
          find.byKey(const Key('ai-acp-client-preset-field')),
          findsNothing,
        );
        await disposePumpedWidgetTree(tester);
      },
    );

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
        await disposePumpedWidgetTree(tester);
      },
    );

    testWidgets(
      'prompts to install the ACP adapter when starting Claude without it',
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
            overrides: [
              databaseProvider.overrideWithValue(db),
              sshServiceProvider.overrideWithValue(
                _FakeSshService(
                  connectionResult: const SshConnectionResult(
                    success: true,
                    connectionId: 77,
                  ),
                ),
              ),
            ],
            child: MaterialApp(
              home: AiStartSessionScreen(
                acpAdapterInstalledChecker: (_, _, _) async => false,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Start Session'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        expect(
          find.byKey(const Key('ai-acp-adapter-install-dialog')),
          findsOneWidget,
        );
        expect(find.text('Install ACP adapter for claude?'), findsOneWidget);
        expect(
          find.byKey(const Key('ai-install-acp-adapter-button')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('ai-continue-without-acp-adapter-button')),
          findsOneWidget,
        );
        await disposePumpedWidgetTree(tester);
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
                '{"provider":"codex","transport":"persistentShell","workingDirectory":"/repo","connectionId":55,"hostId":7}',
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
      expect(find.textContaining('Model: --'), findsOneWidget);
      expect(find.textContaining('Context: --'), findsOneWidget);
      expect(find.textContaining('Mode: --'), findsOneWidget);
      expect(find.textContaining('Transport: Interactive'), findsOneWidget);

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

    testWidgets('restores saved steering preferences in the session sheet', (
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
              title: 'Claude steering',
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
                '{"provider":"claude","transport":"persistentShell","workingDirectory":"/repo","currentModelId":"sonnet","systemPrompt":"Be concise","appendSystemPrompt":"Explain tool calls."}',
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

      await tester.tap(find.byKey(const Key('ai-session-preferences-button')));
      await tester.pumpAndSettle();

      final modelField = tester.widget<TextField>(
        find.byKey(const Key('ai-session-model-field')),
      );
      final systemPromptField = tester.widget<TextField>(
        find.byKey(const Key('ai-session-system-prompt-field')),
      );
      final appendSystemPromptField = tester.widget<TextField>(
        find.byKey(const Key('ai-session-append-system-prompt-field')),
      );

      expect(modelField.controller?.text, 'sonnet');
      expect(systemPromptField.controller?.text, 'Be concise');
      expect(appendSystemPromptField.controller?.text, 'Explain tool calls.');

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('restores saved prompt transport metadata', (tester) async {
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
              title: 'Prompt fallback',
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
                '{"provider":"gemini","transport":"headlessPrompt","workingDirectory":"/repo"}',
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

      expect(find.text('gemini · /repo'), findsOneWidget);
      expect(find.textContaining('Transport: Prompt'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('saving session preferences updates persisted steering state', (
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
              title: 'Codex steering',
            ),
          );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: MaterialApp(
            home: AiChatSessionScreen(
              sessionId: sessionId,
              connectionId: 9,
              provider: AiCliProvider.codex,
              remoteWorkingDirectory: '/workspace',
              autoStartRuntime: false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('ai-session-preferences-button')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('ai-session-model-field')),
        'gpt-5',
      );
      await tester.enterText(
        find.byKey(const Key('ai-session-mode-field')),
        'never',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Model: gpt-5'), findsOneWidget);
      expect(find.textContaining('Mode: never'), findsOneWidget);
      expect(
        find.textContaining(
          'The interactive runtime will relaunch on the next prompt.',
        ),
        findsOneWidget,
      );

      final latestEntry =
          await (db.select(db.aiTimelineEntries)
                ..where((row) => row.sessionId.equals(sessionId))
                ..orderBy([(row) => OrderingTerm.desc(row.id)])
                ..limit(1))
              .getSingle();
      expect(latestEntry.metadata, contains('"currentModelId":"gpt-5"'));
      expect(latestEntry.metadata, contains('"currentModeId":"never"'));

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('saving session preferences can switch transports', (
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
              title: 'Claude transport',
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
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Transport: Interactive'), findsOneWidget);

      await tester.tap(find.byKey(const Key('ai-session-preferences-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ai-session-transport-field')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Prompt').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Transport: Prompt'), findsOneWidget);
      expect(
        find.textContaining('Prompt transport will relaunch on the next turn.'),
        findsOneWidget,
      );

      final latestEntry =
          await (db.select(db.aiTimelineEntries)
                ..where((row) => row.sessionId.equals(sessionId))
                ..orderBy([(row) => OrderingTerm.desc(row.id)])
                ..limit(1))
              .getSingle();
      expect(latestEntry.metadata, contains('"transport":"headlessPrompt"'));

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

    testWidgets('passes slash commands through to runtime', (tester) async {
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
              title: 'Steering queue',
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

      await tester.enterText(
        find.byKey(const Key('ai-chat-input')),
        '/steer Always return concise answers',
      );
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('/steer Always return concise answers'),
        findsOneWidget,
      );
      expect(find.textContaining('Queued steering prompt'), findsNothing);

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

class _FakeSshService extends SshService {
  _FakeSshService({required this.connectionResult});

  final SshConnectionResult connectionResult;

  @override
  Future<SshConnectionResult> connectToHost(
    int hostId, {
    ConnectionProgressCallback? onProgress,
  }) async => connectionResult;
}
