import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/tmux_state.dart';
import 'ssh_service.dart';

const _genericSessionSummaries = <String>{
  'untitled',
  'unnamed',
  'untitled session',
  'new session',
  'empty session',
  'session',
};

const _profileSourcingPrefix =
    '{ . ~/.profile; . ~/.bash_profile; . ~/.zprofile; } '
    '>/dev/null 2>&1; ';
const _remoteSnapshotFieldSeparator = '\x1f';
const _remoteSnapshotBatchSize = 8;

/// Filters noisy discovered sessions and fills in a better display summary
/// when the tool only exposes a working directory.
@visibleForTesting
ToolSessionInfo? normalizeDiscoveredSessionInfo(
  ToolSessionInfo info, {
  String? activeWorkingDirectory,
}) {
  final normalizedSummary = _normalizeDiscoveredSessionSummary(
    info,
    activeWorkingDirectory: activeWorkingDirectory,
  );
  if (normalizedSummary == null) return null;
  return ToolSessionInfo(
    toolName: info.toolName,
    sessionId: info.sessionId,
    workingDirectory: info.workingDirectory,
    lastActive: info.lastActive,
    summary: normalizedSummary,
  );
}

/// Orders sessions from most to least recently updated, leaving untimestamped
/// items at the end.
@visibleForTesting
int compareDiscoveredSessionsByRecency(ToolSessionInfo a, ToolSessionInfo b) {
  final aTime = a.lastActive;
  final bTime = b.lastActive;
  if (aTime != null && bTime != null) {
    final compare = bTime.compareTo(aTime);
    if (compare != 0) return compare;
  } else if (aTime != null) {
    return -1;
  } else if (bTime != null) {
    return 1;
  }

  final toolCompare = a.toolName.compareTo(b.toolName);
  if (toolCompare != 0) return toolCompare;
  return (a.summary ?? '').compareTo(b.summary ?? '');
}

/// Discovered session results plus any tool histories that could not be read.
class DiscoveredSessionsResult {
  /// Creates a new [DiscoveredSessionsResult].
  DiscoveredSessionsResult({
    required Iterable<ToolSessionInfo> sessions,
    Iterable<String> failedTools = const <String>[],
  }) : sessions = List<ToolSessionInfo>.unmodifiable(sessions),
       failedTools = Set<String>.unmodifiable(failedTools);

  /// The sessions that were discovered successfully.
  final List<ToolSessionInfo> sessions;

  /// Tool names whose session history could not be loaded.
  final Set<String> failedTools;

  /// Whether any tool histories failed to load.
  bool get hasFailures => failedTools.isNotEmpty;

  /// A human-readable failure message for the UI.
  String? get failureMessage {
    if (failedTools.isEmpty) return null;
    final orderedTools = failedTools.toList()..sort();
    if (orderedTools.length == 1) {
      return 'Could not load ${orderedTools.first} sessions.';
    }
    final lastTool = orderedTools.removeLast();
    return 'Could not load ${orderedTools.join(', ')} and $lastTool sessions.';
  }
}

/// Whether a tool-level discovery issue should be surfaced to the UI.
///
/// Partial parse issues should stay silent when the tool still yielded usable
/// sessions, so users only see a failure banner when a tool's history could not
/// be loaded at all.
@visibleForTesting
bool shouldSurfaceDiscoveryFailure({
  required bool hadError,
  required int loadedSessionCount,
}) => hadError && loadedSessionCount == 0;

String? _normalizeDiscoveredSessionSummary(
  ToolSessionInfo info, {
  String? activeWorkingDirectory,
}) {
  final normalizedSummary = _sanitizeSessionSummary(
    info.summary,
    sessionId: info.sessionId,
    workingDirectory: info.workingDirectory,
  );
  if (normalizedSummary != null) return normalizedSummary;
  return _directorySummaryFallback(
    info.workingDirectory,
    activeWorkingDirectory: activeWorkingDirectory,
  );
}

String? _sanitizeSessionSummary(
  String? value, {
  required String sessionId,
  String? workingDirectory,
}) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;

  final unquoted = trimmed
      .replaceAll(RegExp(r"""^["'`]+|["'`]+$"""), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (unquoted.isEmpty) return null;

  final lowered = unquoted.toLowerCase();
  if (_genericSessionSummaries.contains(lowered) ||
      lowered == sessionId.toLowerCase() ||
      lowered == _truncateSessionIdValue(sessionId).toLowerCase()) {
    return null;
  }

  final workingDirectorySummary = _directorySummaryFallback(workingDirectory);
  if (workingDirectorySummary != null &&
      lowered == workingDirectorySummary.toLowerCase()) {
    return null;
  }

  final strippedSeparators = unquoted.replaceAll(
    RegExp(r'[\s\-_./\\[\](){}:;,*"`~]+'),
    '',
  );
  if (strippedSeparators.isEmpty) return null;
  return unquoted;
}

String? _directorySummaryFallback(
  String? workingDirectory, {
  String? activeWorkingDirectory,
}) {
  final trimmed = workingDirectory?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  if (activeWorkingDirectory != null &&
      activeWorkingDirectory.isNotEmpty &&
      AgentSessionDiscoveryService._matchesWorkingDirectory(
        activeWorkingDirectory,
        trimmed,
      )) {
    return null;
  }
  final segment = _pathLastSegment(trimmed);
  if (segment.isEmpty || segment == '.' || segment == '~') return null;
  return segment;
}

String _pathLastSegment(String path) =>
    path.split('/').where((segment) => segment.isNotEmpty).lastOrNull ?? path;

String _truncateSessionIdValue(String id) {
  if (id.length <= 12) return id;
  return '${id.substring(0, 8)}…';
}

String _summarizeSessionText(String value, {int maxLength = 80}) {
  final firstMeaningfulLine = value
      .split('\n')
      .map((line) => line.trim())
      .firstWhere((line) => line.isNotEmpty, orElse: () => value.trim());
  final collapsed = firstMeaningfulLine.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (collapsed.length <= maxLength) return collapsed;
  return '${collapsed.substring(0, maxLength - 3)}...';
}

/// Parses Copilot CLI workspace metadata from `workspace.yaml`.
@visibleForTesting
({String? summary, String? workingDirectory, DateTime? updatedAt})
parseCopilotWorkspaceYamlMetadata(String raw) {
  final lines = const LineSplitter().convert(raw);
  String? summary;
  String? workingDirectory;
  DateTime? updatedAt;

  for (var index = 0; index < lines.length; index++) {
    final line = lines[index];

    if (workingDirectory == null) {
      final cwdMatch = RegExp(r'^cwd:\s*(.+)\s*$').firstMatch(line);
      if (cwdMatch != null) {
        workingDirectory = cwdMatch.group(1)!.trim();
      }
    }

    if (updatedAt == null) {
      final updatedAtMatch = RegExp(
        r'^updated_at:\s*(.+)\s*$',
      ).firstMatch(line);
      if (updatedAtMatch != null) {
        updatedAt = DateTime.tryParse(updatedAtMatch.group(1)!.trim());
      }
    }

    if (summary != null) continue;
    final summaryMatch = RegExp(r'^summary:\s*(.*)$').firstMatch(line);
    if (summaryMatch == null) continue;

    final inlineValue = summaryMatch.group(1)!.trimRight();
    if (inlineValue.isEmpty) continue;
    if (inlineValue == '|' ||
        inlineValue == '|-' ||
        inlineValue == '>' ||
        inlineValue == '>-') {
      final blockLines = <String>[];
      while (index + 1 < lines.length) {
        final nextLine = lines[index + 1];
        if (!nextLine.startsWith('  ')) break;
        index += 1;
        blockLines.add(nextLine.substring(2));
      }
      final blockValue = blockLines.join('\n').trim();
      if (blockValue.isNotEmpty) {
        summary = _summarizeSessionText(blockValue);
      }
      continue;
    }

    final normalizedInlineValue = inlineValue.trim();
    if (normalizedInlineValue.isNotEmpty) {
      summary = _summarizeSessionText(normalizedInlineValue);
    }
  }

  return (
    summary: summary,
    workingDirectory: workingDirectory,
    updatedAt: updatedAt,
  );
}

/// Parses Codex rollout metadata from the head of a rollout JSONL file.
@visibleForTesting
({
  String? summary,
  String? workingDirectory,
  DateTime? updatedAt,
  bool parsedAny,
})
parseCodexRolloutMetadata(String raw) {
  String? summary;
  String? workingDirectory;
  DateTime? updatedAt;
  var parsedAny = false;

  for (final line in const LineSplitter().convert(raw)) {
    final decoded = _tryDecodeJsonObject(line);
    if (decoded == null) continue;
    parsedAny = true;

    final payload = _readMapField(decoded, 'payload');
    workingDirectory ??=
        _readStringField(payload, 'cwd') ?? _readStringField(decoded, 'cwd');
    updatedAt ??= _parseDateTimeValue(decoded['timestamp']);

    if (summary != null) continue;
    if (_readStringField(decoded, 'type') != 'event_msg' ||
        _readStringField(payload, 'type') != 'user_message') {
      continue;
    }

    final message = _readStringField(payload, 'message');
    if (message != null && message.trim().isNotEmpty) {
      summary = _summarizeSessionText(message);
    }
  }

  return (
    summary: summary,
    workingDirectory: workingDirectory,
    updatedAt: updatedAt,
    parsedAny: parsedAny,
  );
}

/// Parses Gemini session metadata from a saved chat JSON file.
@visibleForTesting
({
  String? sessionId,
  String? summary,
  String? workingDirectory,
  DateTime? updatedAt,
  bool isSubagent,
  bool parsedAny,
})
parseGeminiSessionMetadata(
  String raw, {
  String? activeWorkingDirectory,
  String? fallbackWorkingDirectory,
}) {
  final decoded = _decodeJsonOrJsonlObject(raw);
  if (decoded == null) {
    return (
      sessionId: null,
      summary: null,
      workingDirectory: fallbackWorkingDirectory,
      updatedAt: null,
      isSubagent: false,
      parsedAny: false,
    );
  }

  final storedSummary = _readStringField(decoded, 'summary');
  final summary = (storedSummary?.trim().isNotEmpty ?? false)
      ? _summarizeSessionText(storedSummary!)
      : _extractGeminiUserSummary(_readListField(decoded, 'messages'));
  final directories = _readListField(decoded, 'directories');
  final resolvedWorkingDirectory =
      _resolveGeminiWorkingDirectory(
        directories,
        activeWorkingDirectory: activeWorkingDirectory,
      ) ??
      fallbackWorkingDirectory;

  return (
    sessionId: _readStringField(decoded, 'sessionId'),
    summary: summary,
    workingDirectory: resolvedWorkingDirectory,
    updatedAt:
        _parseDateTimeValue(decoded['lastUpdated']) ??
        _parseDateTimeValue(decoded['startTime']),
    isSubagent: _readStringField(decoded, 'kind') == 'subagent',
    parsedAny: true,
  );
}

/// Parses a single batched remote file snapshot record.
///
/// This exists primarily for tests that exercise the remote snapshot transport
/// without requiring a live SSH session.
@visibleForTesting
({String path, String content, DateTime? modifiedAt})?
parseRemoteFileSnapshotLine(String line) {
  final trimmed = line.trimRight();
  if (trimmed.isEmpty) return null;
  final parts = trimmed.split(_remoteSnapshotFieldSeparator);
  if (parts.length < 3) return null;

  final path = parts[0].trim();
  if (path.isEmpty) return null;

  final rawModifiedAt = parts[1].trim();
  final modifiedAtEpoch = int.tryParse(rawModifiedAt);
  final rawContent = parts[2].trim();

  try {
    final decodedContent = utf8.decode(
      base64.decode(rawContent),
      allowMalformed: true,
    );
    return (
      path: path,
      content: decodedContent,
      modifiedAt: modifiedAtEpoch == null || modifiedAtEpoch <= 0
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              modifiedAtEpoch > 9999999999
                  ? modifiedAtEpoch
                  : modifiedAtEpoch * 1000,
            ),
    );
  } on FormatException {
    return null;
  }
}

/// Prioritizes Gemini session files that appear to belong to the active
/// project before scanning sibling-project history.
@visibleForTesting
List<String> prioritizeGeminiSessionFilePaths(
  Iterable<String> sessionPaths, {
  String? activeWorkingDirectory,
  int? preferredCount,
}) {
  final normalizedPaths = sessionPaths
      .map((path) => path.trim())
      .where((path) => path.isNotEmpty)
      .toList(growable: false);
  if (normalizedPaths.isEmpty) return const [];

  final activeProjectName =
      activeWorkingDirectory != null && activeWorkingDirectory.trim().isNotEmpty
      ? _pathLastSegment(activeWorkingDirectory)
      : null;
  if (activeProjectName == null || activeProjectName.isEmpty) {
    return normalizedPaths;
  }

  final matching = <String>[];
  final unknown = <String>[];
  final otherProjects = <String>[];
  for (final path in normalizedPaths) {
    final pathParts = path.split('/');
    final chatsIndex = pathParts.indexOf('chats');
    final projectName = chatsIndex > 0 ? pathParts[chatsIndex - 1].trim() : '';
    if (projectName.isEmpty) {
      unknown.add(path);
      continue;
    }
    if (projectName == activeProjectName) {
      matching.add(path);
      continue;
    }
    otherProjects.add(path);
  }

  final targetCount = preferredCount != null && preferredCount > 0
      ? preferredCount
      : normalizedPaths.length;
  final prioritized = <String>[...matching, ...unknown];
  if (prioritized.length >= targetCount || otherProjects.isEmpty) {
    return prioritized.take(targetCount).toList(growable: false);
  }

  prioritized.addAll(otherProjects.take(targetCount - prioritized.length));
  return prioritized;
}

/// Discovers recent AI coding tool sessions on remote hosts by scanning
/// known session storage locations.
///
/// Each tool stores session history differently. This service encapsulates
/// the per-tool discovery logic and presents a unified list of
/// [ToolSessionInfo] entries.
class AgentSessionDiscoveryService {
  /// Creates a new [AgentSessionDiscoveryService].
  const AgentSessionDiscoveryService();

  /// Discovers recent sessions across all supported tools for the given
  /// [workingDirectory] on the remote host.
  ///
  /// Each tool's sessions are discovered separately, normalized to drop
  /// noisy placeholder entries, and then sorted globally by recency.
  /// Limits to [maxPerTool] sessions per tool to keep results manageable.
  ///
  /// Returns both the successfully parsed sessions and any tool histories that
  /// could not be loaded, so the UI can distinguish parse failures from an
  /// actually empty history.
  ///
  /// When [workingDirectory] is available, sessions are filtered to that
  /// directory whenever the tool exposes enough path information to do so.
  Future<DiscoveredSessionsResult> discoverSessions(
    SshSession session, {
    String? workingDirectory,
    int maxPerTool = 12,
  }) async {
    final tasks = _startToolDiscovery(
      session,
      workingDirectory: workingDirectory,
      maxPerTool: maxPerTool,
    );
    final results = await Future.wait(tasks.map((task) => task.future));
    return _buildDiscoveredSessionsResult(
      results,
      workingDirectory: workingDirectory,
      maxPerTool: maxPerTool,
    );
  }

  /// Streams cumulative discovery results as each provider completes.
  ///
  /// The final emitted value matches [discoverSessions], while intermediate
  /// values surface any providers that have already completed so the UI can
  /// render partial results without waiting for the slowest tool.
  Stream<DiscoveredSessionsResult> discoverSessionsStream(
    SshSession session, {
    String? workingDirectory,
    int maxPerTool = 12,
  }) {
    late final StreamController<DiscoveredSessionsResult> controller;
    var cancelled = false;
    controller = StreamController<DiscoveredSessionsResult>(
      onListen: () {
        final tasks = _startToolDiscovery(
          session,
          workingDirectory: workingDirectory,
          maxPerTool: maxPerTool,
        );
        final completed = List<_ToolDiscoveryResult?>.filled(
          tasks.length,
          null,
        );

        for (final indexedTask in tasks.indexed) {
          final index = indexedTask.$1;
          final task = indexedTask.$2;
          task.future.then(
            (result) {
              if (cancelled || controller.isClosed) {
                return;
              }
              completed[index] = result;
              final loadedResults = completed.whereType<_ToolDiscoveryResult>();
              final isComplete = loadedResults.length == tasks.length;
              controller.add(
                _buildDiscoveredSessionsResult(
                  loadedResults,
                  workingDirectory: workingDirectory,
                  maxPerTool: maxPerTool,
                  includeFailures: isComplete,
                  allowWorkingDirectoryFallback: isComplete,
                ),
              );
              if (isComplete && !controller.isClosed) {
                unawaited(controller.close());
              }
            },
            onError: (error, stackTrace) {
              if (cancelled || controller.isClosed) {
                return;
              }
              completed[index] = _ToolDiscoveryResult.failure(task.toolName);
              final loadedResults = completed.whereType<_ToolDiscoveryResult>();
              final isComplete = loadedResults.length == tasks.length;
              controller.add(
                _buildDiscoveredSessionsResult(
                  loadedResults,
                  workingDirectory: workingDirectory,
                  maxPerTool: maxPerTool,
                  includeFailures: isComplete,
                  allowWorkingDirectoryFallback: isComplete,
                ),
              );
              if (isComplete && !controller.isClosed) {
                unawaited(controller.close());
              }
            },
          );
        }
      },
      onCancel: () {
        cancelled = true;
      },
    );
    return controller.stream;
  }

  /// Builds the shell command to resume a specific session.
  ///
  /// If the session has a [ToolSessionInfo.workingDirectory], the command
  /// `cd`s there first so the CLI finds its project context.
  String buildResumeCommand(ToolSessionInfo info) {
    final resume = switch (info.toolName) {
      'Claude Code' => 'claude --resume ${_shellQuote(info.sessionId)}',
      'Codex' => 'codex resume ${_shellQuote(info.sessionId)}',
      'Copilot CLI' => 'copilot --resume ${_shellQuote(info.sessionId)}',
      'Gemini CLI' => 'gemini --resume ${_shellQuote(info.sessionId)}',
      'OpenCode' =>
        info.sessionId == '_continue'
            ? 'opencode --continue'
            : 'opencode --session ${_shellQuote(info.sessionId)}',
      _ => info.toolName.toLowerCase(),
    };

    final dir = info.workingDirectory;
    if (dir != null && dir.isNotEmpty) {
      return 'cd ${_shellQuote(dir)} && $resume';
    }
    return resume;
  }

  List<_ToolDiscoveryTask> _startToolDiscovery(
    SshSession session, {
    String? workingDirectory,
    int maxPerTool = 12,
  }) => [
    _ToolDiscoveryTask(
      toolName: 'Claude Code',
      future: _discoverClaudeSessions(session, workingDirectory, maxPerTool),
    ),
    _ToolDiscoveryTask(
      toolName: 'Codex',
      future: _discoverCodexSessions(session, maxPerTool),
    ),
    _ToolDiscoveryTask(
      toolName: 'Copilot CLI',
      future: _discoverCopilotSessions(session, maxPerTool),
    ),
    _ToolDiscoveryTask(
      toolName: 'Gemini CLI',
      future: _discoverGeminiSessions(session, workingDirectory, maxPerTool),
    ),
    _ToolDiscoveryTask(
      toolName: 'OpenCode',
      future: _discoverOpenCodeSessions(session, maxPerTool),
    ),
  ];

  DiscoveredSessionsResult _buildDiscoveredSessionsResult(
    Iterable<_ToolDiscoveryResult> results, {
    String? workingDirectory,
    int maxPerTool = 12,
    bool includeFailures = true,
    bool allowWorkingDirectoryFallback = true,
  }) {
    final resultList = results.toList(growable: false);
    final all = resultList
        .expand((result) => result.sessions)
        .map(
          (info) => normalizeDiscoveredSessionInfo(
            info,
            activeWorkingDirectory: workingDirectory,
          ),
        )
        .whereType<ToolSessionInfo>()
        .toList();

    if (workingDirectory != null && workingDirectory.isNotEmpty) {
      final filtered = _limitDiscoveredSessionsPerTool(
        all
            .where(
              (session) => _matchesWorkingDirectory(
                workingDirectory,
                session.workingDirectory,
              ),
            )
            .toList(),
        maxPerTool,
      );
      if (filtered.isNotEmpty || !allowWorkingDirectoryFallback) {
        return DiscoveredSessionsResult(
          sessions: filtered,
          failedTools: _visibleDiscoveryFailures(
            resultList,
            includeFailures: includeFailures,
          ),
        );
      }
    }

    return DiscoveredSessionsResult(
      sessions: _limitDiscoveredSessionsPerTool(all, maxPerTool),
      failedTools: _visibleDiscoveryFailures(
        resultList,
        includeFailures: includeFailures,
      ),
    );
  }

  Set<String> _visibleDiscoveryFailures(
    Iterable<_ToolDiscoveryResult> results, {
    required bool includeFailures,
  }) {
    if (!includeFailures) {
      return const <String>{};
    }
    return results
        .where(
          (result) => shouldSurfaceDiscoveryFailure(
            hadError: result.hadError,
            loadedSessionCount: result.sessions.length,
          ),
        )
        .map((result) => result.toolName)
        .toSet();
  }

  // ── Claude Code ────────────────────────────────────────────────────────
  // Sessions: ~/.claude/projects/<path-hash>/*.jsonl
  // Index:    ~/.claude/history.jsonl

  Future<_ToolDiscoveryResult> _discoverClaudeSessions(
    SshSession session,
    String? workingDirectory,
    int max,
  ) async {
    try {
      // Read more lines than needed to account for duplicate sessionIds
      // (e.g. multiple history entries for the same active session).
      final tailCount = max * 5;
      final output = await _exec(
        session,
        'tail -n $tailCount ~/.claude/history.jsonl 2>/dev/null',
      );
      if (output.trim().isEmpty) {
        return const _ToolDiscoveryResult.success('Claude Code', []);
      }

      final historyEntries = <Map<String, dynamic>>[];
      final seenIds = <String>{};
      for (final line in output.trim().split('\n').reversed) {
        if (line.trim().isEmpty) continue;
        try {
          final decoded = jsonDecode(line);
          if (decoded is! Map<String, dynamic>) continue;
          final sessionId = decoded['sessionId'] as String? ?? '';
          if (sessionId.isEmpty || seenIds.contains(sessionId)) continue;
          seenIds.add(sessionId);
          historyEntries.add(decoded);
        } on Object {
          // Ignore malformed lines.
        }
      }

      final sessionFilesById = await _findClaudeSessionFiles(session, seenIds);
      final metadataByPath = await _readClaudeSessionMetadataBatch(
        session,
        sessionFilesById.values,
      );
      final sessions = <ToolSessionInfo>[];
      for (final decoded in historyEntries) {
        try {
          final sessionId = decoded['sessionId'] as String? ?? '';
          if (sessionId.isEmpty) continue;

          // timestamp may be int (epoch ms) or String (ISO 8601).
          DateTime? lastActive;
          final rawTs = decoded['timestamp'];
          if (rawTs is int) {
            lastActive = DateTime.fromMillisecondsSinceEpoch(rawTs);
          } else if (rawTs is String) {
            lastActive = DateTime.tryParse(rawTs);
          }

          String? summary;
          final sessionFilePath = sessionFilesById[sessionId] ?? '';
          if (sessionFilePath.isNotEmpty) {
            final metadata = metadataByPath[sessionFilePath];
            lastActive ??= metadata?.modifiedAt;
            summary = _firstNonEmpty([
              metadata?.customTitle,
              metadata?.agentName,
              metadata?.lastPrompt,
            ]);
          }

          // Fall back to history index fields.
          final display = decoded['display'] as String?;
          summary ??=
              decoded['title'] as String? ??
              decoded['query'] as String? ??
              (display != null && !display.startsWith('/') ? display : null);

          sessions.add(
            ToolSessionInfo(
              toolName: 'Claude Code',
              sessionId: sessionId,
              workingDirectory:
                  decoded['directory'] as String? ??
                  decoded['project'] as String?,
              lastActive: lastActive,
              summary: summary,
            ),
          );
          if (sessions.length >= max) break;
        } on Object {
          continue;
        }
      }
      return _ToolDiscoveryResult.success('Claude Code', sessions);
    } on Object {
      return const _ToolDiscoveryResult.failure('Claude Code');
    }
  }

  // ── Codex CLI ──────────────────────────────────────────────────────────
  // Sessions: ~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl

  Future<_ToolDiscoveryResult> _discoverCodexSessions(
    SshSession session,
    int max,
  ) async {
    try {
      final scanLimit = max * 5;
      final output = await _exec(
        session,
        'find ~/.codex/sessions -name "rollout-*.jsonl" -type f '
        '-exec ls -1t {} + 2>/dev/null | head -n $scanLimit',
      );
      if (output.trim().isEmpty) {
        return const _ToolDiscoveryResult.success('Codex', []);
      }

      final sessionIndex = await _readCodexSessionIndex(session, scanLimit);
      final rolloutPaths = output
          .trim()
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList(growable: false);
      final rolloutSnapshots = await _readRemoteFileSnapshots(
        session,
        rolloutPaths.map((path) => _RemoteFileReadRequest.headLines(path, 80)),
      );
      final sessions = <ToolSessionInfo>[];
      var hadError = sessionIndex.hadError;

      for (final filePath in rolloutPaths) {
        final fileName = filePath.split('/').last.replaceAll('.jsonl', '');
        final threadId = _extractCodexThreadId(fileName);
        final threadInfo = threadId != null
            ? sessionIndex.entries[threadId]
            : null;

        var summary = threadInfo?.threadName;
        String? workingDirectory;
        var lastActive = threadInfo?.updatedAt;

        try {
          final rolloutHead = rolloutSnapshots[filePath]?.content ?? '';
          final metadata = parseCodexRolloutMetadata(rolloutHead);
          if (rolloutHead.trim().isNotEmpty && !metadata.parsedAny) {
            hadError = true;
          }
          summary ??= metadata.summary;
          workingDirectory = metadata.workingDirectory;
          lastActive ??= metadata.updatedAt;
        } on Object {
          hadError = true;
        }

        lastActive ??= rolloutSnapshots[filePath]?.modifiedAt;

        sessions.add(
          ToolSessionInfo(
            toolName: 'Codex',
            sessionId: fileName,
            workingDirectory: workingDirectory,
            lastActive: lastActive,
            summary: summary ?? _truncateId(fileName),
          ),
        );
      }
      return _ToolDiscoveryResult.success(
        'Codex',
        sessions,
        hadError: hadError,
      );
    } on Object {
      return const _ToolDiscoveryResult.failure('Codex');
    }
  }

  Future<_CodexSessionIndexResult> _readCodexSessionIndex(
    SshSession session,
    int scanLimit,
  ) async {
    try {
      final output = await _exec(
        session,
        'tail -n ${scanLimit * 5} ~/.codex/session_index.jsonl 2>/dev/null',
      );
      if (output.trim().isEmpty) {
        return const _CodexSessionIndexResult(entries: {});
      }

      final entries = <String, _CodexSessionIndexEntry>{};
      var hadError = false;
      for (final line in output.trim().split('\n').reversed) {
        if (line.trim().isEmpty) continue;
        final decoded = _tryDecodeJsonObject(line);
        if (decoded == null) {
          hadError = true;
          continue;
        }
        final id = _readStringField(decoded, 'id');
        if (id == null || id.isEmpty || entries.containsKey(id)) continue;
        entries[id] = _CodexSessionIndexEntry(
          threadName: _readStringField(decoded, 'thread_name'),
          updatedAt: _parseDateTimeValue(decoded['updated_at']),
        );
      }
      return _CodexSessionIndexResult(entries: entries, hadError: hadError);
    } on Object {
      return const _CodexSessionIndexResult(entries: {}, hadError: true);
    }
  }

  // ── Copilot CLI ────────────────────────────────────────────────────────
  // Sessions: ~/.copilot/session-state/<session-id>/

  Future<_ToolDiscoveryResult> _discoverCopilotSessions(
    SshSession session,
    int max,
  ) async {
    try {
      final scanLimit = max * 5;
      final output = await _exec(
        session,
        'find ~/.copilot/session-state -mindepth 2 -maxdepth 2 '
        '-name workspace.yaml -type f '
        '-exec ls -1t {} + 2>/dev/null | head -n $scanLimit',
      );
      if (output.trim().isEmpty) {
        return const _ToolDiscoveryResult.success('Copilot CLI', []);
      }

      final workspacePaths = output
          .trim()
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList(growable: false);
      final workspaceSnapshots = await _readRemoteFileSnapshots(
        session,
        workspacePaths.map(
          (workspacePath) =>
              _RemoteFileReadRequest.headBytes(workspacePath, 16 * 1024),
        ),
      );

      var hadError = false;
      final planHeadPaths = <String>[];
      final sessionDrafts =
          <
            ({
              String sessionId,
              String planPath,
              String? workingDirectory,
              DateTime? lastActive,
              String? summary,
            })
          >[];
      for (final workspacePath in workspacePaths) {
        final dirPath = workspacePath.replaceFirst(
          RegExp(r'/workspace\.yaml$'),
          '/',
        );
        final dirName = dirPath.split('/').where((s) => s.isNotEmpty).last;
        final snapshot = workspaceSnapshots[workspacePath];
        final yaml = snapshot?.content ?? '';

        String? summary;
        String? workingDirectory;
        DateTime? lastActive;
        if (yaml.trim().isNotEmpty) {
          final metadata = parseCopilotWorkspaceYamlMetadata(yaml);
          summary = metadata.summary;
          workingDirectory = metadata.workingDirectory;
          lastActive = metadata.updatedAt;
        } else if (snapshot == null) {
          hadError = true;
        }
        lastActive ??= snapshot?.modifiedAt;

        final planPath = '${dirPath}plan.md';
        if (summary == null || summary.isEmpty) {
          planHeadPaths.add(planPath);
        }
        sessionDrafts.add((
          sessionId: dirName,
          planPath: planPath,
          workingDirectory: workingDirectory,
          lastActive: lastActive,
          summary: summary,
        ));
      }

      final planSnapshots = await _readRemoteFileSnapshots(
        session,
        planHeadPaths.map((path) => _RemoteFileReadRequest.headLines(path, 3)),
      );
      final sessions = sessionDrafts
          .map((draft) {
            var summary = draft.summary;
            if (summary == null || summary.isEmpty) {
              final planHead = planSnapshots[draft.planPath]?.content ?? '';
              if (planHead.trim().isNotEmpty) {
                for (final planLine in planHead.trim().split('\n')) {
                  final cleaned = planLine
                      .replaceAll(RegExp(r'^#+\s*'), '')
                      .trim();
                  if (cleaned.isNotEmpty && cleaned.length > 3) {
                    summary = _summarizeSessionText(cleaned);
                    break;
                  }
                }
              }
            }

            return ToolSessionInfo(
              toolName: 'Copilot CLI',
              sessionId: draft.sessionId,
              workingDirectory: draft.workingDirectory,
              lastActive: draft.lastActive,
              summary: summary ?? _truncateId(draft.sessionId),
            );
          })
          .toList(growable: false);
      return _ToolDiscoveryResult.success(
        'Copilot CLI',
        sessions,
        hadError: hadError,
      );
    } on Object {
      return const _ToolDiscoveryResult.failure('Copilot CLI');
    }
  }

  // ── Gemini CLI ─────────────────────────────────────────────────────────
  // `gemini --list-sessions` outputs a human-readable list scoped to
  // the current project. Each line looks like:
  //   1. Title text (time ago) [session-uuid]
  // Falls back to scanning chat JSON files if the CLI is unavailable.

  Future<_ToolDiscoveryResult> _discoverGeminiSessions(
    SshSession session,
    String? workingDirectory,
    int max,
  ) async {
    try {
      // Preferred: use the CLI's own session list.
      final cdPrefix = workingDirectory != null && workingDirectory.isNotEmpty
          ? 'cd ${_shellQuote(workingDirectory)} && '
          : '';
      final cliOutput = await _exec(
        session,
        '${cdPrefix}gemini --list-sessions 2>/dev/null',
      );
      if (cliOutput.contains('[') && cliOutput.contains(']')) {
        final parsed = _parseGeminiCliOutput(cliOutput, workingDirectory);
        if (parsed.isNotEmpty) {
          return _ToolDiscoveryResult.success(
            'Gemini CLI',
            parsed.take(max * 5).toList(),
          );
        }
      }

      // Fallback: scan chat JSON files directly.
      return _discoverGeminiSessionsFromFiles(session, workingDirectory, max);
    } on Object {
      return const _ToolDiscoveryResult.failure('Gemini CLI');
    }
  }

  /// Parses Gemini CLI `--list-sessions` text output.
  ///
  /// Each session line matches:
  ///   `N. Title text (time ago) [session-uuid]`
  static final _geminiSessionLinePattern = RegExp(
    r'^\s*\d+\.\s+(.+?)\s+\([^)]+\)\s+\[([0-9a-f-]+)\]\s*$',
  );

  List<ToolSessionInfo> _parseGeminiCliOutput(
    String output,
    String? workingDirectory,
  ) {
    final sessions = <ToolSessionInfo>[];
    for (final line in output.split('\n')) {
      final match = _geminiSessionLinePattern.firstMatch(line);
      if (match == null) continue;

      final title = match.group(1)!.trim();
      final id = match.group(2)!.trim();

      sessions.add(
        ToolSessionInfo(
          toolName: 'Gemini CLI',
          sessionId: id,
          workingDirectory: workingDirectory,
          summary: title.length > 80 ? '${title.substring(0, 77)}...' : title,
        ),
      );
    }
    return sessions;
  }

  Future<_ToolDiscoveryResult> _discoverGeminiSessionsFromFiles(
    SshSession session,
    String? workingDirectory,
    int max,
  ) async {
    final scanLimit = max * 5;
    final output = await _exec(
      session,
      r'find ~/.gemini/tmp \( -name "session-*.json" -o -name "session-*.jsonl" \) '
      '-path "*/chats/*" -type f '
      '-exec ls -1t {} + 2>/dev/null | head -n $scanLimit',
    );
    if (output.trim().isEmpty) {
      return const _ToolDiscoveryResult.success('Gemini CLI', []);
    }

    final sessionPaths = output
        .trim()
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
    final prioritizedSessionPaths = prioritizeGeminiSessionFilePaths(
      sessionPaths,
      activeWorkingDirectory: workingDirectory,
      preferredCount: max * 2,
    );
    final sessionSnapshots = await _readRemoteFileSnapshots(
      session,
      prioritizedSessionPaths.map(
        (filePath) => _RemoteFileReadRequest.headBytes(filePath, 32 * 1024),
      ),
    );

    var hadError = false;
    final sessions = await Future.wait(
      prioritizedSessionPaths.map((filePath) async {
        final fileName = filePath
            .split('/')
            .last
            .replaceAll('.jsonl', '')
            .replaceAll('.json', '');

        final pathParts = filePath.split('/');
        final chatsIdx = pathParts.indexOf('chats');
        final projectDir = chatsIdx > 0 ? pathParts[chatsIdx - 1] : null;
        final fallbackWorkingDirectory =
            projectDir != null &&
                workingDirectory != null &&
                _pathLastSegment(workingDirectory) == projectDir
            ? workingDirectory
            : null;

        String? summary;
        var sessionWorkingDirectory = fallbackWorkingDirectory;
        DateTime? lastActive;
        String? sessionId = fileName;
        try {
          final sessionRecord = sessionSnapshots[filePath]?.content ?? '';
          final metadata = parseGeminiSessionMetadata(
            sessionRecord,
            activeWorkingDirectory: workingDirectory,
            fallbackWorkingDirectory: fallbackWorkingDirectory,
          );
          if (sessionRecord.trim().isNotEmpty && !metadata.parsedAny) {
            hadError = true;
            return null;
          }
          if (metadata.isSubagent) return null;
          summary = metadata.summary;
          sessionWorkingDirectory = metadata.workingDirectory;
          lastActive = metadata.updatedAt;
          final discoveredSessionId = metadata.sessionId;
          if (discoveredSessionId != null && discoveredSessionId.isNotEmpty) {
            sessionId = discoveredSessionId;
          }
        } on Object {
          hadError = true;
          return null;
        }

        lastActive ??= sessionSnapshots[filePath]?.modifiedAt;

        return ToolSessionInfo(
          toolName: 'Gemini CLI',
          sessionId: sessionId,
          workingDirectory: sessionWorkingDirectory,
          lastActive: lastActive,
          summary: summary ?? projectDir ?? _truncateId(fileName),
        );
      }),
    );
    return _ToolDiscoveryResult.success(
      'Gemini CLI',
      sessions.whereType<ToolSessionInfo>().toList(growable: false),
      hadError: hadError,
    );
  }

  // ── OpenCode ───────────────────────────────────────────────────────────
  // `opencode session list --format json` is the cleanest source of truth.
  // It returns renamed titles, directory, and timestamps. Falls back to
  // the SQLite database or JSON files if the CLI is unavailable.

  Future<_ToolDiscoveryResult> _discoverOpenCodeSessions(
    SshSession session,
    int max,
  ) async {
    try {
      final scanLimit = max * 5;
      var hadError = false;
      // Preferred: use the CLI's own JSON output.
      final cliOutput = await _exec(
        session,
        'opencode session list --format json -n $scanLimit 2>/dev/null',
      );
      if (cliOutput.trim().startsWith('[')) {
        try {
          return _ToolDiscoveryResult.success(
            'OpenCode',
            _parseOpenCodeCliJson(cliOutput),
          );
        } on Object {
          hadError = true;
          // Fall through to the SQLite fallback.
        }
      }

      // Fallback: query the SQLite database directly.
      // Use ASCII Unit Separator (\x1f) to avoid collision with pipes
      // in session titles or directory paths.
      final dbOutput = await _exec(
        session,
        r'SEP=$(printf "\037"); sqlite3 -separator "$SEP" '
        '~/.local/share/opencode/opencode.db '
        "'SELECT id, title, directory, time_updated "
        'FROM session '
        'WHERE parent_id IS NULL '
        'AND time_archived IS NULL '
        'ORDER BY time_updated DESC '
        "LIMIT $scanLimit;' 2>/dev/null",
      );
      if (dbOutput.trim().isNotEmpty) {
        return _ToolDiscoveryResult.success(
          'OpenCode',
          _parseOpenCodeDbOutput(dbOutput),
          hadError: hadError,
        );
      }

      return _ToolDiscoveryResult.success('OpenCode', [], hadError: hadError);
    } on Object {
      return const _ToolDiscoveryResult.failure('OpenCode');
    }
  }

  List<ToolSessionInfo> _parseOpenCodeCliJson(String raw) {
    final decoded = jsonDecode(raw.trim());
    if (decoded is! List) return const [];

    return decoded.whereType<Map<String, dynamic>>().map((entry) {
      final id = entry['id'] as String? ?? '';
      final title = entry['title'] as String? ?? '';
      final directory = entry['directory'] as String?;

      DateTime? lastActive;
      final updated = entry['updated'];
      if (updated is int) {
        lastActive = _dateTimeFromEpoch(updated);
      } else if (updated is String) {
        lastActive = DateTime.tryParse(updated);
      }

      return ToolSessionInfo(
        toolName: 'OpenCode',
        sessionId: id,
        workingDirectory: directory,
        lastActive: lastActive,
        summary: title.isNotEmpty ? title : _truncateId(id),
      );
    }).toList();
  }

  List<ToolSessionInfo> _parseOpenCodeDbOutput(String output) {
    final sessions = <ToolSessionInfo>[];
    for (final line in output.trim().split('\n')) {
      if (line.trim().isEmpty) continue;
      final parts = line.split('\x1f');
      if (parts.length < 3) continue;

      final id = parts[0].trim();
      final title = parts[1].trim();
      final directory = parts[2].trim();
      DateTime? lastActive;
      if (parts.length >= 4) {
        final ts = int.tryParse(parts[3].trim());
        if (ts != null) {
          lastActive = _dateTimeFromEpoch(ts);
        }
      }

      sessions.add(
        ToolSessionInfo(
          toolName: 'OpenCode',
          sessionId: id,
          workingDirectory: directory.isNotEmpty ? directory : null,
          lastActive: lastActive,
          summary: title.isNotEmpty ? title : _truncateId(id),
        ),
      );
    }
    return sessions;
  }

  // ── Helpers ────────────────────────────────────────────────────────────

  Future<String> _exec(SshSession session, String command) async {
    final execSession = await session.execute(
      '$_profileSourcingPrefix$command',
    );
    try {
      final results = await Future.wait([
        execSession.stdout.cast<List<int>>().transform(utf8.decoder).join(),
        execSession.stderr.cast<List<int>>().transform(utf8.decoder).join(),
      ]).timeout(const Duration(seconds: 10), onTimeout: () => ['', '']);
      return results[0];
    } finally {
      execSession.close();
    }
  }

  Future<Map<String, String>> _findClaudeSessionFiles(
    SshSession session,
    Iterable<String> sessionIds,
  ) async {
    final uniqueSessionIds = sessionIds
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (uniqueSessionIds.isEmpty) {
      return const <String, String>{};
    }

    final nameFilters = uniqueSessionIds
        .map((id) => '-name ${_shellQuote('$id.jsonl')}')
        .join(' -o ');
    final output = await _exec(
      session,
      'find ~/.claude/projects -type f \\( $nameFilters \\) -print 2>/dev/null',
    );

    final filesById = <String, String>{};
    for (final rawLine in output.split('\n')) {
      final path = rawLine.trim();
      if (path.isEmpty) continue;
      final fileName = path.split('/').last;
      if (!fileName.endsWith('.jsonl')) continue;
      final sessionId = fileName.substring(
        0,
        fileName.length - '.jsonl'.length,
      );
      filesById.putIfAbsent(sessionId, () => path);
    }
    return filesById;
  }

  Future<Map<String, _RemoteFileSnapshot>> _readRemoteFileSnapshots(
    SshSession session,
    Iterable<_RemoteFileReadRequest> requests,
  ) async {
    final uniqueRequests = <String, _RemoteFileReadRequest>{};
    for (final request in requests) {
      final path = request.path.trim();
      if (path.isEmpty || uniqueRequests.containsKey(path)) {
        continue;
      }
      uniqueRequests[path] = request;
    }
    if (uniqueRequests.isEmpty) {
      return const <String, _RemoteFileSnapshot>{};
    }

    final snapshots = <String, _RemoteFileSnapshot>{};
    for (final chunk in _chunked(
      uniqueRequests.values.toList(growable: false),
      _remoteSnapshotBatchSize,
    )) {
      final output = await _exec(
        session,
        _buildRemoteFileSnapshotCommand(chunk),
      );
      for (final line in output.split('\n')) {
        final parsed = parseRemoteFileSnapshotLine(line);
        if (parsed == null) continue;
        snapshots[parsed.path] = _RemoteFileSnapshot(
          path: parsed.path,
          content: parsed.content,
          modifiedAt: parsed.modifiedAt,
        );
      }
    }
    return snapshots;
  }

  String _buildRemoteFileSnapshotCommand(
    List<_RemoteFileReadRequest> requests,
  ) {
    final reads = requests
        .map((request) {
          final readCommand = switch (request.mode) {
            _RemoteFileReadMode.headBytes =>
              '"\$HEAD_BIN" -c ${request.limit} ${_shellQuote(request.path)}',
            _RemoteFileReadMode.headLines =>
              '"\$HEAD_BIN" -n ${request.limit} ${_shellQuote(request.path)}',
          };
          return '''
if [ -f ${_shellQuote(request.path)} ]; then
  __mtime=\$( ( "\$STAT_BIN" -c %Y ${_shellQuote(request.path)} 2>/dev/null || "\$STAT_BIN" -f %m ${_shellQuote(request.path)} 2>/dev/null ) | "\$HEAD_BIN" -n 1 )
  __content=\$($readCommand 2>/dev/null | "\$BASE64_BIN" | "\$TR_BIN" -d '\n')
  printf '%s$_remoteSnapshotFieldSeparator%s$_remoteSnapshotFieldSeparator%s\n' ${_shellQuote(request.path)} "\$__mtime" "\$__content"
fi
''';
        })
        .join(';');
    return '''
STAT_BIN=\$(command -v stat 2>/dev/null || printf /usr/bin/stat)
HEAD_BIN=\$(command -v head 2>/dev/null || printf /usr/bin/head)
BASE64_BIN=\$(command -v base64 2>/dev/null || printf /usr/bin/base64)
TR_BIN=\$(command -v tr 2>/dev/null || printf /usr/bin/tr)
$reads
''';
  }

  Future<Map<String, _ClaudeSessionMetadataSnapshot>>
  _readClaudeSessionMetadataBatch(
    SshSession session,
    Iterable<String> paths,
  ) async {
    final normalizedPaths = paths
        .map((path) => path.trim())
        .where((path) => path.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (normalizedPaths.isEmpty) {
      return const <String, _ClaudeSessionMetadataSnapshot>{};
    }

    final metadataByPath = <String, _ClaudeSessionMetadataSnapshot>{};
    for (final chunk in _chunked(normalizedPaths, _remoteSnapshotBatchSize)) {
      final output = await _exec(
        session,
        _buildClaudeMetadataBatchCommand(chunk),
      );
      for (final line in output.split('\n')) {
        final parsed = parseRemoteFileSnapshotLine(line);
        if (parsed == null) continue;
        final metadata = _parseClaudeMetadataSnapshot(parsed.content);
        metadataByPath[parsed.path] = _ClaudeSessionMetadataSnapshot(
          modifiedAt: parsed.modifiedAt,
          customTitle: metadata.customTitle,
          agentName: metadata.agentName,
          lastPrompt: metadata.lastPrompt,
        );
      }
    }
    return metadataByPath;
  }

  String _buildClaudeMetadataBatchCommand(List<String> paths) {
    final awkScript = _shellQuote(r'''
match($0, /"customTitle":"([^"]*)"/, value) { customTitle = value[1] }
match($0, /"agentName":"([^"]*)"/, value) { agentName = value[1] }
match($0, /"lastPrompt":"([^"]*)"/, value) { lastPrompt = value[1] }
END {
  printf "customTitle=%s\nagentName=%s\nlastPrompt=%s\n", customTitle, agentName, lastPrompt
}
''');
    final reads = paths
        .map(
          (path) =>
              '''
if [ -f ${_shellQuote(path)} ]; then
  __mtime=\$( ( "\$STAT_BIN" -c %Y ${_shellQuote(path)} 2>/dev/null || "\$STAT_BIN" -f %m ${_shellQuote(path)} 2>/dev/null ) | "\$HEAD_BIN" -n 1 )
  __content=\$("\$AWK_BIN" $awkScript ${_shellQuote(path)} 2>/dev/null | "\$BASE64_BIN" | "\$TR_BIN" -d '\n')
  printf '%s$_remoteSnapshotFieldSeparator%s$_remoteSnapshotFieldSeparator%s\n' ${_shellQuote(path)} "\$__mtime" "\$__content"
fi
''',
        )
        .join(';');
    return '''
STAT_BIN=\$(command -v stat 2>/dev/null || printf /usr/bin/stat)
HEAD_BIN=\$(command -v head 2>/dev/null || printf /usr/bin/head)
AWK_BIN=\$(command -v awk 2>/dev/null || printf /usr/bin/awk)
BASE64_BIN=\$(command -v base64 2>/dev/null || printf /usr/bin/base64)
TR_BIN=\$(command -v tr 2>/dev/null || printf /usr/bin/tr)
$reads
''';
  }

  ({String customTitle, String agentName, String lastPrompt})
  _parseClaudeMetadataSnapshot(String output) {
    var customTitle = '';
    var agentName = '';
    var lastPrompt = '';
    for (final line in output.split('\n')) {
      final separator = line.indexOf('=');
      if (separator <= 0) {
        continue;
      }
      final key = line.substring(0, separator);
      final value = line.substring(separator + 1).trim();
      switch (key) {
        case 'customTitle':
          customTitle = value;
        case 'agentName':
          agentName = value;
        case 'lastPrompt':
          lastPrompt = value;
      }
    }
    return (
      customTitle: customTitle,
      agentName: agentName,
      lastPrompt: lastPrompt,
    );
  }

  Iterable<List<T>> _chunked<T>(List<T> values, int chunkSize) sync* {
    for (var start = 0; start < values.length; start += chunkSize) {
      final end = start + chunkSize < values.length
          ? start + chunkSize
          : values.length;
      yield values.sublist(start, end);
    }
  }

  DateTime _dateTimeFromEpoch(int epoch) => DateTime.fromMillisecondsSinceEpoch(
    epoch > 9999999999 ? epoch : epoch * 1000,
  );

  static String _shellQuote(String value) =>
      "'${value.replaceAll("'", "'\"'\"'")}'";

  List<ToolSessionInfo> _limitDiscoveredSessionsPerTool(
    List<ToolSessionInfo> sessions,
    int maxPerTool,
  ) {
    final groupedSessions = <String, List<ToolSessionInfo>>{};
    for (final session in sessions) {
      groupedSessions
          .putIfAbsent(session.toolName, () => <ToolSessionInfo>[])
          .add(session);
    }

    final limited = <ToolSessionInfo>[];
    for (final toolSessions in groupedSessions.values) {
      toolSessions.sort(compareDiscoveredSessionsByRecency);
      limited.addAll(toolSessions.take(maxPerTool));
    }
    limited.sort(compareDiscoveredSessionsByRecency);
    return limited;
  }

  static String? _firstNonEmpty(Iterable<String?> values) {
    for (final value in values) {
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  static bool _matchesWorkingDirectory(
    String expectedDirectory,
    String? sessionDirectory,
  ) {
    if (sessionDirectory == null || sessionDirectory.isEmpty) return false;
    return sessionDirectory == expectedDirectory ||
        _pathLastSegment(sessionDirectory) ==
            _pathLastSegment(expectedDirectory);
  }

  static String _truncateId(String id) => _truncateSessionIdValue(id);
}

class _ToolDiscoveryResult {
  const _ToolDiscoveryResult.success(
    this.toolName,
    this.sessions, {
    this.hadError = false,
  });

  const _ToolDiscoveryResult.failure(this.toolName)
    : sessions = const <ToolSessionInfo>[],
      hadError = true;

  final String toolName;
  final List<ToolSessionInfo> sessions;
  final bool hadError;
}

class _ToolDiscoveryTask {
  const _ToolDiscoveryTask({required this.toolName, required this.future});

  final String toolName;
  final Future<_ToolDiscoveryResult> future;
}

class _CodexSessionIndexResult {
  const _CodexSessionIndexResult({
    required this.entries,
    this.hadError = false,
  });

  final Map<String, _CodexSessionIndexEntry> entries;
  final bool hadError;
}

class _CodexSessionIndexEntry {
  const _CodexSessionIndexEntry({this.threadName, this.updatedAt});

  final String? threadName;
  final DateTime? updatedAt;
}

enum _RemoteFileReadMode { headBytes, headLines }

class _RemoteFileReadRequest {
  const _RemoteFileReadRequest.headBytes(this.path, this.limit)
    : mode = _RemoteFileReadMode.headBytes;

  const _RemoteFileReadRequest.headLines(this.path, this.limit)
    : mode = _RemoteFileReadMode.headLines;

  final String path;
  final int limit;
  final _RemoteFileReadMode mode;
}

class _RemoteFileSnapshot {
  const _RemoteFileSnapshot({
    required this.path,
    required this.content,
    this.modifiedAt,
  });

  final String path;
  final String content;
  final DateTime? modifiedAt;
}

class _ClaudeSessionMetadataSnapshot {
  const _ClaudeSessionMetadataSnapshot({
    this.modifiedAt,
    this.customTitle = '',
    this.agentName = '',
    this.lastPrompt = '',
  });

  final DateTime? modifiedAt;
  final String customTitle;
  final String agentName;
  final String lastPrompt;
}

Map<String, dynamic>? _tryDecodeJsonObject(String raw) {
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) return decoded;
  } on FormatException {
    return null;
  }
  return null;
}

Map<String, dynamic>? _decodeJsonOrJsonlObject(String raw) {
  final direct = _tryDecodeJsonObject(raw.trim());
  if (direct != null) return direct;

  Map<String, dynamic>? lastObject;
  for (final line in const LineSplitter().convert(raw)) {
    final decoded = _tryDecodeJsonObject(line.trim());
    if (decoded == null) continue;
    lastObject = decoded;
    if (decoded.containsKey('sessionId') || decoded.containsKey('messages')) {
      return decoded;
    }
  }
  return lastObject;
}

Map<String, dynamic>? _readMapField(Map<String, dynamic>? map, String key) {
  final value = map?[key];
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map(
      (innerKey, innerValue) => MapEntry('$innerKey', innerValue),
    );
  }
  return null;
}

List<dynamic>? _readListField(Map<String, dynamic>? map, String key) {
  final value = map?[key];
  return value is List ? value : null;
}

String? _readStringField(Map<String, dynamic>? map, String key) {
  final value = map?[key];
  return value is String ? value : null;
}

DateTime? _parseDateTimeValue(Object? value) {
  if (value is String) return DateTime.tryParse(value);
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
  return null;
}

String? _extractCodexThreadId(String fileName) {
  final match = RegExp(
    r'([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})$',
  ).firstMatch(fileName);
  return match?.group(1);
}

String? _extractGeminiUserSummary(List<dynamic>? messages) {
  if (messages == null) return null;
  for (final message in messages.whereType<Map>()) {
    final messageMap = message.map((key, value) => MapEntry('$key', value));
    if (_readStringField(messageMap, 'type') != 'user') continue;

    final content = _readListField(messageMap, 'content');
    if (content != null) {
      for (final part in content.whereType<Map>()) {
        final partMap = part.map((key, value) => MapEntry('$key', value));
        final text = _readStringField(partMap, 'text');
        if (text != null && text.trim().isNotEmpty) {
          return _summarizeSessionText(text);
        }
      }
    }

    final displayContent = _readStringField(messageMap, 'displayContent');
    if (displayContent != null && displayContent.trim().isNotEmpty) {
      return _summarizeSessionText(displayContent);
    }
  }
  return null;
}

String? _resolveGeminiWorkingDirectory(
  List<dynamic>? directories, {
  String? activeWorkingDirectory,
}) {
  final values = directories
      ?.whereType<String>()
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toList(growable: false);
  if (values == null || values.isEmpty) return null;

  if (activeWorkingDirectory != null && activeWorkingDirectory.isNotEmpty) {
    for (final value in values) {
      if (value == activeWorkingDirectory ||
          _pathLastSegment(value) == _pathLastSegment(activeWorkingDirectory)) {
        return value;
      }
    }
  }

  if (values.length == 1) return values.first;
  return null;
}

/// Provider for [AgentSessionDiscoveryService].
final agentSessionDiscoveryServiceProvider =
    Provider<AgentSessionDiscoveryService>(
      (ref) => const AgentSessionDiscoveryService(),
    );
