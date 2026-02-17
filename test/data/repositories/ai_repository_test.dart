// ignore_for_file: public_member_api_docs

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:monkeyssh/data/database/database.dart';
import 'package:monkeyssh/data/repositories/ai_repository.dart';

void main() {
  late AppDatabase db;
  late AiRepository repository;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repository = AiRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('AiRepository - Workspaces', () {
    test('insertWorkspace creates and retrieves workspace', () async {
      final id = await repository.insertWorkspace(
        AiWorkspacesCompanion.insert(name: 'Flutty', path: '/tmp/flutty'),
      );

      final workspace = await repository.getWorkspaceById(id);

      expect(workspace, isNotNull);
      expect(workspace!.name, 'Flutty');
      expect(workspace.path, '/tmp/flutty');
    });

    test('updateWorkspace modifies workspace', () async {
      final id = await repository.insertWorkspace(
        AiWorkspacesCompanion.insert(name: 'Original', path: '/tmp/original'),
      );
      final workspace = await repository.getWorkspaceById(id);

      final success = await repository.updateWorkspace(
        workspace!.copyWith(name: 'Updated'),
      );

      expect(success, isTrue);
      final updated = await repository.getWorkspaceById(id);
      expect(updated!.name, 'Updated');
    });
  });

  group('AiRepository - Sessions', () {
    test('getSessionsByWorkspace filters by workspace', () async {
      final workspace1 = await repository.insertWorkspace(
        AiWorkspacesCompanion.insert(name: 'One', path: '/tmp/one'),
      );
      final workspace2 = await repository.insertWorkspace(
        AiWorkspacesCompanion.insert(name: 'Two', path: '/tmp/two'),
      );

      await repository.insertSession(
        AiSessionsCompanion.insert(workspaceId: workspace1, title: 'Session 1'),
      );
      await repository.insertSession(
        AiSessionsCompanion.insert(workspaceId: workspace2, title: 'Session 2'),
      );

      final sessions = await repository.getSessionsByWorkspace(workspace1);

      expect(sessions, hasLength(1));
      expect(sessions.first.title, 'Session 1');
    });

    test('getRecentSessions orders by updated timestamp', () async {
      final workspaceId = await repository.insertWorkspace(
        AiWorkspacesCompanion.insert(name: 'Order', path: '/tmp/order'),
      );
      final firstSessionId = await repository.insertSession(
        AiSessionsCompanion.insert(workspaceId: workspaceId, title: 'Older'),
      );
      final secondSessionId = await repository.insertSession(
        AiSessionsCompanion.insert(workspaceId: workspaceId, title: 'Newer'),
      );

      final firstSession = await repository.getSessionById(firstSessionId);
      await repository.updateSession(
        firstSession!.copyWith(updatedAt: DateTime(2000)),
      );
      await repository.insertTimelineEntry(
        AiTimelineEntriesCompanion.insert(
          sessionId: secondSessionId,
          role: 'status',
          message: 'touch',
        ),
      );

      final sessions = await repository.getRecentSessions(limit: 2);
      expect(sessions, hasLength(2));
      expect(sessions.first.id, secondSessionId);
    });

    test('updateSessionStatus stores lifecycle status', () async {
      final workspaceId = await repository.insertWorkspace(
        AiWorkspacesCompanion.insert(name: 'Lifecycle', path: '/tmp/lifecycle'),
      );
      final sessionId = await repository.insertSession(
        AiSessionsCompanion.insert(workspaceId: workspaceId, title: 'Session'),
      );

      final updated = await repository.updateSessionStatus(
        sessionId: sessionId,
        status: 'detached',
      );

      final session = await repository.getSessionById(sessionId);
      expect(updated, isTrue);
      expect(session, isNotNull);
      expect(session!.status, 'detached');
    });
  });

  group('AiRepository - Timeline', () {
    test('getTimelineBySession returns entries for a session', () async {
      final workspaceId = await repository.insertWorkspace(
        AiWorkspacesCompanion.insert(name: 'Flutty', path: '/tmp/flutty'),
      );
      final sessionId = await repository.insertSession(
        AiSessionsCompanion.insert(
          workspaceId: workspaceId,
          title: 'Schema session',
        ),
      );

      await repository.insertTimelineEntry(
        AiTimelineEntriesCompanion.insert(
          sessionId: sessionId,
          role: 'user',
          message: 'Create schema',
        ),
      );
      await repository.insertTimelineEntry(
        AiTimelineEntriesCompanion.insert(
          sessionId: sessionId,
          role: 'assistant',
          message: 'Done',
        ),
      );

      final entries = await repository.getTimelineBySession(sessionId);

      expect(entries, hasLength(2));
      expect(entries.first.role, 'user');
      expect(entries.last.role, 'assistant');
    });

    test('insertTimelineEntry updates parent session updatedAt', () async {
      final workspaceId = await repository.insertWorkspace(
        AiWorkspacesCompanion.insert(name: 'Touch', path: '/tmp/touch'),
      );
      final sessionId = await repository.insertSession(
        AiSessionsCompanion.insert(workspaceId: workspaceId, title: 'Session'),
      );
      final session = await repository.getSessionById(sessionId);
      await repository.updateSession(
        session!.copyWith(updatedAt: DateTime(2001)),
      );

      await repository.insertTimelineEntry(
        AiTimelineEntriesCompanion.insert(
          sessionId: sessionId,
          role: 'user',
          message: 'Refresh',
        ),
      );

      final updatedSession = await repository.getSessionById(sessionId);
      expect(updatedSession, isNotNull);
      expect(updatedSession!.updatedAt.year, greaterThan(2001));
    });

    test('deleteWorkspace cascades sessions and timeline entries', () async {
      final workspaceId = await repository.insertWorkspace(
        AiWorkspacesCompanion.insert(name: 'Cascade', path: '/tmp/cascade'),
      );
      final sessionId = await repository.insertSession(
        AiSessionsCompanion.insert(workspaceId: workspaceId, title: 'Session'),
      );

      await repository.insertTimelineEntry(
        AiTimelineEntriesCompanion.insert(
          sessionId: sessionId,
          role: 'user',
          message: 'Hello',
        ),
      );

      final deleted = await repository.deleteWorkspace(workspaceId);

      expect(deleted, 1);
      final sessions = await repository.getSessionsByWorkspace(workspaceId);
      final entries = await repository.getTimelineBySession(sessionId);
      expect(sessions, isEmpty);
      expect(entries, isEmpty);
    });
  });
}
