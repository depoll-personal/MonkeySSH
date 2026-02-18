import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/database.dart';

/// Repository for managing AI workspaces, sessions, and timeline entries.
class AiRepository {
  /// Creates a new [AiRepository].
  AiRepository(this._db);

  final AppDatabase _db;

  /// Get all AI workspaces.
  Future<List<AiWorkspace>> getAllWorkspaces() =>
      _db.select(_db.aiWorkspaces).get();

  /// Watch all AI workspaces.
  Stream<List<AiWorkspace>> watchAllWorkspaces() =>
      _db.select(_db.aiWorkspaces).watch();

  /// Get an AI workspace by ID.
  Future<AiWorkspace?> getWorkspaceById(int id) => (_db.select(
    _db.aiWorkspaces,
  )..where((w) => w.id.equals(id))).getSingleOrNull();

  /// Insert a new AI workspace.
  Future<int> insertWorkspace(AiWorkspacesCompanion workspace) =>
      _db.into(_db.aiWorkspaces).insert(workspace);

  /// Update an existing AI workspace.
  Future<bool> updateWorkspace(AiWorkspace workspace) =>
      _db.update(_db.aiWorkspaces).replace(workspace);

  /// Delete an AI workspace.
  Future<int> deleteWorkspace(int id) => _db.transaction(() async {
    final sessionIds = await (_db.select(
      _db.aiSessions,
    )..where((s) => s.workspaceId.equals(id))).map((s) => s.id).get();

    if (sessionIds.isNotEmpty) {
      await (_db.delete(
        _db.aiTimelineEntries,
      )..where((e) => e.sessionId.isIn(sessionIds))).go();
    }

    await (_db.delete(
      _db.aiSessions,
    )..where((s) => s.workspaceId.equals(id))).go();
    return (_db.delete(_db.aiWorkspaces)..where((w) => w.id.equals(id))).go();
  });

  /// Get AI sessions by workspace.
  Future<List<AiSession>> getSessionsByWorkspace(int workspaceId) =>
      (_db.select(_db.aiSessions)
            ..where((s) => s.workspaceId.equals(workspaceId))
            ..orderBy([(s) => OrderingTerm.desc(s.createdAt)]))
          .get();

  /// Watch AI sessions by workspace.
  Stream<List<AiSession>> watchSessionsByWorkspace(int workspaceId) =>
      (_db.select(_db.aiSessions)
            ..where((s) => s.workspaceId.equals(workspaceId))
            ..orderBy([(s) => OrderingTerm.desc(s.createdAt)]))
          .watch();

  /// Get recent AI sessions ordered by latest activity.
  Future<List<AiSession>> getRecentSessions({int limit = 20}) =>
      (_db.select(_db.aiSessions)
            ..orderBy([
              (s) => OrderingTerm.desc(s.updatedAt),
              (s) => OrderingTerm.desc(s.createdAt),
            ])
            ..limit(limit))
          .get();

  /// Watch recent AI sessions ordered by latest activity.
  Stream<List<AiSession>> watchRecentSessions({int limit = 20}) =>
      (_db.select(_db.aiSessions)
            ..orderBy([
              (s) => OrderingTerm.desc(s.updatedAt),
              (s) => OrderingTerm.desc(s.createdAt),
            ])
            ..limit(limit))
          .watch();

  /// Get an AI session by ID.
  Future<AiSession?> getSessionById(int id) => (_db.select(
    _db.aiSessions,
  )..where((s) => s.id.equals(id))).getSingleOrNull();

  /// Get workspace linked to a session.
  Future<AiWorkspace?> getWorkspaceForSession(int sessionId) async {
    final session = await getSessionById(sessionId);
    if (session == null) {
      return null;
    }
    return getWorkspaceById(session.workspaceId);
  }

  /// Insert a new AI session.
  Future<int> insertSession(AiSessionsCompanion session) =>
      _db.into(_db.aiSessions).insert(session);

  /// Update an existing AI session.
  Future<bool> updateSession(AiSession session) =>
      _db.update(_db.aiSessions).replace(session);

  /// Delete an AI session.
  Future<int> deleteSession(int id) => _db.transaction(() async {
    await (_db.delete(
      _db.aiTimelineEntries,
    )..where((e) => e.sessionId.equals(id))).go();
    return (_db.delete(_db.aiSessions)..where((s) => s.id.equals(id))).go();
  });

  /// Get timeline entries by AI session.
  Future<List<AiTimelineEntry>> getTimelineBySession(int sessionId) =>
      (_db.select(_db.aiTimelineEntries)
            ..where((e) => e.sessionId.equals(sessionId))
            ..orderBy([
              (e) => OrderingTerm.asc(e.createdAt),
              (e) => OrderingTerm.asc(e.id),
            ]))
          .get();

  /// Watch timeline entries by AI session.
  Stream<List<AiTimelineEntry>> watchTimelineBySession(int sessionId) =>
      (_db.select(_db.aiTimelineEntries)
            ..where((e) => e.sessionId.equals(sessionId))
            ..orderBy([
              (e) => OrderingTerm.asc(e.createdAt),
              (e) => OrderingTerm.asc(e.id),
            ]))
          .watch();

  /// Get latest timeline entry for an AI session.
  Future<AiTimelineEntry?> getLatestTimelineEntry(int sessionId) =>
      (_db.select(_db.aiTimelineEntries)
            ..where((e) => e.sessionId.equals(sessionId))
            ..orderBy([
              (e) => OrderingTerm.desc(e.createdAt),
              (e) => OrderingTerm.desc(e.id),
            ])
            ..limit(1))
          .getSingleOrNull();

  /// Update status and timestamp metadata for an AI session.
  Future<bool> updateSessionStatus({
    required int sessionId,
    required String status,
    DateTime? completedAt,
  }) async {
    final rowCount =
        await (_db.update(
          _db.aiSessions,
        )..where((session) => session.id.equals(sessionId))).write(
          AiSessionsCompanion(
            status: Value(status),
            updatedAt: Value(DateTime.now()),
            completedAt: Value(completedAt),
          ),
        );
    return rowCount > 0;
  }

  /// Insert a new timeline entry.
  Future<int> insertTimelineEntry(AiTimelineEntriesCompanion entry) async =>
      _db.transaction(() async {
        final insertedId = await _db.into(_db.aiTimelineEntries).insert(entry);
        if (entry.sessionId.present) {
          final sessionId = entry.sessionId.value;
          await (_db.update(_db.aiSessions)
                ..where((session) => session.id.equals(sessionId)))
              .write(AiSessionsCompanion(updatedAt: Value(DateTime.now())));
        }
        return insertedId;
      });

  /// Delete a timeline entry.
  Future<int> deleteTimelineEntry(int id) =>
      (_db.delete(_db.aiTimelineEntries)..where((e) => e.id.equals(id))).go();

  /// Update the message text of an existing timeline entry.
  Future<void> updateTimelineEntryMessage(int id, String message) =>
      (_db.update(_db.aiTimelineEntries)..where((e) => e.id.equals(id))).write(
        AiTimelineEntriesCompanion(message: Value(message)),
      );
}

/// Provider for [AiRepository].
final aiRepositoryProvider = Provider<AiRepository>(
  (ref) => AiRepository(ref.watch(databaseProvider)),
);
