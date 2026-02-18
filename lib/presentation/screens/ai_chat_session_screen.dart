import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/database.dart';
import '../../data/repositories/ai_repository.dart';
import '../../domain/models/ai_cli_provider.dart';
import '../../domain/services/ai_runtime_event_parser_pipeline.dart';
import '../../domain/services/ai_runtime_service.dart';
import '../../domain/services/ai_session_metadata.dart';
import '../../domain/services/shell_escape.dart';
import '../../domain/services/ssh_service.dart';
import '../widgets/ai_composer_autocomplete.dart';

/// Chat session screen with real-time timeline rendering.
class AiChatSessionScreen extends ConsumerStatefulWidget {
  /// Creates an [AiChatSessionScreen].
  const AiChatSessionScreen({
    required this.sessionId,
    this.connectionId,
    this.provider,
    this.executableOverride,
    this.remoteWorkingDirectory,
    this.hostId,
    this.isResumeRequest = false,
    this.autoStartRuntime = true,
    this.remoteFileSuggestionLoader,
    super.key,
  });

  /// AI session ID in persistence storage.
  final int sessionId;

  /// SSH connection ID used for the runtime process.
  final int? connectionId;

  /// CLI provider used for this session.
  final AiCliProvider? provider;

  /// Optional ACP-compatible client launch command override.
  final String? executableOverride;

  /// Remote working directory for command startup.
  final String? remoteWorkingDirectory;

  /// Host identifier used for reconnecting detached sessions.
  final int? hostId;

  /// Whether the screen was opened as a history resume request.
  final bool isResumeRequest;

  /// Whether runtime launch should happen automatically on screen open.
  final bool autoStartRuntime;

  /// Optional remote file loader used by composer autocomplete.
  final Future<List<String>> Function()? remoteFileSuggestionLoader;

  @override
  ConsumerState<AiChatSessionScreen> createState() =>
      _AiChatSessionScreenState();
}

class _AiChatSessionScreenState extends ConsumerState<AiChatSessionScreen> {
  late final TextEditingController _promptController;
  late final FocusNode _promptFocusNode;
  late final ScrollController _scrollController;
  late AiComposerAutocompleteEngine _composerAutocompleteEngine;

  StreamSubscription<AiTimelineEvent>? _runtimeTimelineSubscription;
  Future<List<String>>? _remoteFileSuggestionsInFlight;
  List<String>? _cachedRemoteFileSuggestions;
  List<AiComposerSuggestion> _composerSuggestions =
      const <AiComposerSuggestion>[];
  var _selectedComposerSuggestionIndex = 0;
  var _composerSuggestionRevision = 0;
  _AiSessionRuntimeContext? _sessionContext;
  bool _runtimeStarted = false;
  bool _reconnecting = false;
  bool _sending = false;
  var _lastRenderedTimelineCount = 0;
  _RuntimeAttachmentState _runtimeAttachmentState =
      _RuntimeAttachmentState.restoring;

  @override
  void initState() {
    super.initState();
    _promptController = TextEditingController();
    _promptFocusNode = FocusNode();
    _scrollController = ScrollController();
    _composerAutocompleteEngine = AiComposerAutocompleteEngine(
      slashCommands: (widget.provider ?? AiCliProvider.claude)
          .capabilities
          .composerSlashCommands,
    );
    _promptController.addListener(_handleComposerInputChanged);
    _promptFocusNode.addListener(_handleComposerInputChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final parser = ref.read(aiRuntimeEventParserPipelineProvider);
      final runtimeEvents = ref.read(aiRuntimeServiceProvider).events;
      _runtimeTimelineSubscription = parser
          .bind(runtimeEvents)
          .listen(
            _handleRuntimeTimelineEvent,
            onError: _handleRuntimeTimelineStreamError,
          );
      unawaited(_initializeSessionContext());
    });
  }

  @override
  void dispose() {
    _promptController.removeListener(_handleComposerInputChanged);
    _promptFocusNode.removeListener(_handleComposerInputChanged);
    _promptController.dispose();
    _promptFocusNode.dispose();
    _scrollController.dispose();
    unawaited(_runtimeTimelineSubscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final timelineAsync = ref.watch(_aiTimelineProvider(widget.sessionId));
    final theme = Theme.of(context);
    final sessionContext = _sessionContext;
    final provider =
        sessionContext?.provider ?? widget.provider ?? AiCliProvider.claude;
    final executableLabel =
        sessionContext?.executableOverride ??
        widget.executableOverride ??
        provider.executable;
    final workingDirectory =
        sessionContext?.remoteWorkingDirectory ??
        widget.remoteWorkingDirectory ??
        '~';
    final runtimeLabel = switch (_runtimeAttachmentState) {
      _RuntimeAttachmentState.restoring => 'Restoring',
      _RuntimeAttachmentState.attached => 'Attached',
      _RuntimeAttachmentState.resumed => 'Resumed',
      _RuntimeAttachmentState.detached => 'Detached',
    };
    final runtimeBadgeColor = switch (_runtimeAttachmentState) {
      _RuntimeAttachmentState.detached => theme.colorScheme.errorContainer,
      _RuntimeAttachmentState.resumed => theme.colorScheme.tertiaryContainer,
      _RuntimeAttachmentState.restoring => theme.colorScheme.secondaryContainer,
      _RuntimeAttachmentState.attached => theme.colorScheme.primaryContainer,
    };
    final runtimeTextColor = switch (_runtimeAttachmentState) {
      _RuntimeAttachmentState.detached => theme.colorScheme.onErrorContainer,
      _RuntimeAttachmentState.resumed => theme.colorScheme.onTertiaryContainer,
      _RuntimeAttachmentState.restoring =>
        theme.colorScheme.onSecondaryContainer,
      _RuntimeAttachmentState.attached => theme.colorScheme.onPrimaryContainer,
    };

    return Scaffold(
      appBar: AppBar(
        title: Text('AI Session #${widget.sessionId}'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(30),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                Icon(Icons.memory_outlined, size: 14, color: theme.hintColor),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '$executableLabel · $workingDirectory',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                Container(
                  key: const Key('ai-runtime-state-badge'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: runtimeBadgeColor,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    runtimeLabel,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: runtimeTextColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 920),
                  child: timelineAsync.when(
                    loading: () => const Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    error: (error, _) =>
                        Center(child: Text('Failed to load timeline: $error')),
                    data: (entries) {
                      if (entries.isEmpty) {
                        _lastRenderedTimelineCount = 0;
                        return const Center(
                          child: Text(
                            'No timeline entries yet. Send a message to begin.',
                          ),
                        );
                      }
                      if (_lastRenderedTimelineCount != entries.length) {
                        _lastRenderedTimelineCount = entries.length;
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (!mounted) {
                            return;
                          }
                          _scrollToBottom();
                        });
                      }
                      return ListView.builder(
                        key: const Key('ai-timeline-list'),
                        controller: _scrollController,
                        padding: const EdgeInsets.all(12),
                        itemCount: entries.length,
                        itemBuilder: (context, index) =>
                            AiTimelineEntryTile(entry: entries[index]),
                      );
                    },
                  ),
                ),
              ),
            ),
            _buildComposer(context),
          ],
        ),
      ),
    );
  }

  Widget _buildComposer(BuildContext context) {
    final shortcuts = <ShortcutActivator, VoidCallback>{
      if (_composerSuggestions.isNotEmpty) ...{
        const SingleActivator(LogicalKeyboardKey.arrowDown):
            _selectNextComposerSuggestion,
        const SingleActivator(LogicalKeyboardKey.arrowUp):
            _selectPreviousComposerSuggestion,
        const SingleActivator(LogicalKeyboardKey.enter):
            _selectCurrentComposerSuggestion,
      },
    };

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: Theme.of(context).colorScheme.outline.withAlpha(30),
          ),
        ),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 920),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_composerSuggestions.isNotEmpty)
                Container(
                  key: const Key('ai-chat-autocomplete-list'),
                  constraints: const BoxConstraints(maxHeight: 180),
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _composerSuggestions.length,
                    itemBuilder: (context, index) {
                      final suggestion = _composerSuggestions[index];
                      final selected =
                          index == _selectedComposerSuggestionIndex;
                      return ListTile(
                        key: Key('ai-chat-autocomplete-item-$index'),
                        dense: true,
                        selected: selected,
                        onTap: () => _applyComposerSuggestion(suggestion),
                        leading: Icon(
                          suggestion.type ==
                                  AiComposerSuggestionType.slashCommand
                              ? Icons.terminal_outlined
                              : Icons.attach_file_outlined,
                          size: 18,
                        ),
                        title: Text(
                          suggestion.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    },
                  ),
                ),
              Row(
                children: [
                  Expanded(
                    child: CallbackShortcuts(
                      bindings: shortcuts,
                      child: TextField(
                        key: const Key('ai-chat-input'),
                        focusNode: _promptFocusNode,
                        controller: _promptController,
                        maxLines: 4,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => unawaited(_sendPrompt()),
                        decoration: const InputDecoration(
                          hintText: 'Send a prompt…',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ),
                  if (_runtimeAttachmentState ==
                      _RuntimeAttachmentState.detached) ...[
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      key: const Key('ai-reconnect-runtime-button'),
                      onPressed: _reconnecting
                          ? null
                          : () => unawaited(_reconnectRuntime()),
                      icon: _reconnecting
                          ? const SizedBox.square(
                              dimension: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.link, size: 16),
                      label: Text(
                        _reconnecting ? 'Reconnecting...' : 'Reconnect',
                      ),
                    ),
                  ],
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _sending ? null : () => unawaited(_sendPrompt()),
                    child: _sending
                        ? const SizedBox.square(
                            dimension: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _handleComposerInputChanged() {
    unawaited(_refreshComposerSuggestions());
  }

  Future<void> _refreshComposerSuggestions() async {
    final revision = ++_composerSuggestionRevision;
    if (!_promptFocusNode.hasFocus) {
      if (_composerSuggestions.isNotEmpty && mounted) {
        setState(() {
          _composerSuggestions = const <AiComposerSuggestion>[];
          _selectedComposerSuggestionIndex = 0;
        });
      }
      return;
    }

    final textValue = _promptController.value;
    if (_composerAutocompleteEngine.requiresRemoteFileSuggestions(textValue)) {
      try {
        await _ensureRemoteFileSuggestionsLoaded();
      } on Exception {
        _cachedRemoteFileSuggestions = const <String>[];
      }
    }
    if (!mounted || revision != _composerSuggestionRevision) {
      return;
    }

    final suggestions = _composerAutocompleteEngine.suggestionsFor(
      textValue,
      remoteFiles: _cachedRemoteFileSuggestions ?? const <String>[],
    );
    setState(() {
      _composerSuggestions = suggestions;
      _selectedComposerSuggestionIndex = _composerSuggestions.isEmpty
          ? 0
          : _selectedComposerSuggestionIndex >= _composerSuggestions.length
          ? _composerSuggestions.length - 1
          : _selectedComposerSuggestionIndex;
    });
  }

  Future<List<String>> _ensureRemoteFileSuggestionsLoaded() {
    final cached = _cachedRemoteFileSuggestions;
    if (cached != null) {
      return Future<List<String>>.value(cached);
    }
    final inFlight = _remoteFileSuggestionsInFlight;
    if (inFlight != null) {
      return inFlight;
    }

    final future = _loadRemoteFileSuggestions().then((paths) {
      final deduplicated = paths.toSet().toList(growable: false)..sort();
      _cachedRemoteFileSuggestions = deduplicated;
      return deduplicated;
    });
    _remoteFileSuggestionsInFlight = future;
    return future.whenComplete(() {
      _remoteFileSuggestionsInFlight = null;
    });
  }

  Future<List<String>> _loadRemoteFileSuggestions() async {
    final loader = widget.remoteFileSuggestionLoader;
    if (loader != null) {
      return loader();
    }

    final context = _sessionContext;
    if (context == null || context.connectionId == null) {
      return const <String>[];
    }

    final session = ref
        .read(activeSessionsProvider.notifier)
        .getSession(context.connectionId!);
    if (session == null) {
      return const <String>[];
    }

    final escapedDirectory = shellEscape(context.remoteWorkingDirectory);
    final process = await session.execute(
      'cd $escapedDirectory && '
      'find . -maxdepth 4 -type f 2>/dev/null | sed "s#^./##" | head -n 250',
    );
    final output = await process.stdout
        .cast<List<int>>()
        .transform(utf8.decoder)
        .join();
    await process.done;
    return output
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
  }

  void _selectNextComposerSuggestion() {
    if (_composerSuggestions.isEmpty) {
      return;
    }
    setState(() {
      _selectedComposerSuggestionIndex =
          (_selectedComposerSuggestionIndex + 1) % _composerSuggestions.length;
    });
  }

  void _selectPreviousComposerSuggestion() {
    if (_composerSuggestions.isEmpty) {
      return;
    }
    setState(() {
      _selectedComposerSuggestionIndex =
          (_selectedComposerSuggestionIndex - 1) < 0
          ? _composerSuggestions.length - 1
          : _selectedComposerSuggestionIndex - 1;
    });
  }

  void _selectCurrentComposerSuggestion() {
    if (_composerSuggestions.isEmpty) {
      return;
    }
    _applyComposerSuggestion(
      _composerSuggestions[_selectedComposerSuggestionIndex],
    );
  }

  void _applyComposerSuggestion(AiComposerSuggestion suggestion) {
    final updatedValue = _composerAutocompleteEngine.applySuggestion(
      _promptController.value,
      suggestion,
    );
    _promptController.value = updatedValue;
    _promptFocusNode.requestFocus();
    unawaited(_refreshComposerSuggestions());
  }

  Future<void> _initializeSessionContext() async {
    try {
      final context = await _loadSessionRuntimeContext();
      if (!mounted) {
        return;
      }
      setState(() {
        _sessionContext = context;
        _runtimeAttachmentState = _resolveRuntimeAttachmentState(context);
        _composerAutocompleteEngine = AiComposerAutocompleteEngine(
          slashCommands: context.provider.capabilities.composerSlashCommands,
        );
      });
      if (widget.autoStartRuntime) {
        await _startRuntimeIfNeeded();
      }
    } on Exception {
      if (!mounted) {
        return;
      }
      setState(() {
        _runtimeAttachmentState = _RuntimeAttachmentState.detached;
      });
    }
  }

  Future<_AiSessionRuntimeContext> _loadSessionRuntimeContext() async {
    final repository = ref.read(aiRepositoryProvider);
    final session = await repository.getSessionById(widget.sessionId);
    if (session == null) {
      throw StateError('Session ${widget.sessionId} not found.');
    }
    final workspace = await repository.getWorkspaceById(session.workspaceId);
    final timelineEntries = await repository.getTimelineBySession(
      widget.sessionId,
    );

    var latestMetadata = const <String, dynamic>{};
    for (final entry in timelineEntries.reversed) {
      final metadata = AiSessionMetadata.decode(entry.metadata);
      if (metadata.isNotEmpty) {
        latestMetadata = metadata;
        break;
      }
    }

    final provider =
        widget.provider ??
        AiSessionMetadata.readProvider(latestMetadata) ??
        AiCliProvider.claude;
    final executableOverride =
        widget.executableOverride ??
        AiSessionMetadata.readString(latestMetadata, 'executableOverride');
    final connectionId =
        widget.connectionId ??
        AiSessionMetadata.readInt(latestMetadata, 'connectionId');
    final hostId =
        widget.hostId ?? AiSessionMetadata.readInt(latestMetadata, 'hostId');
    final remoteWorkingDirectory =
        widget.remoteWorkingDirectory ??
        AiSessionMetadata.readString(latestMetadata, 'workingDirectory') ??
        workspace?.path ??
        '~';

    return _AiSessionRuntimeContext(
      connectionId: connectionId,
      hostId: hostId,
      provider: provider,
      executableOverride: executableOverride,
      remoteWorkingDirectory: remoteWorkingDirectory,
      resumedSession: widget.isResumeRequest || widget.connectionId == null,
    );
  }

  _RuntimeAttachmentState _resolveRuntimeAttachmentState(
    _AiSessionRuntimeContext context,
  ) {
    final connectionId = context.connectionId;
    if (connectionId == null || !_hasActiveConnection(connectionId)) {
      return _RuntimeAttachmentState.detached;
    }
    if (context.resumedSession) {
      return _RuntimeAttachmentState.resumed;
    }
    return _RuntimeAttachmentState.attached;
  }

  bool _hasActiveConnection(int connectionId) =>
      ref.read(activeSessionsProvider.notifier).getSession(connectionId) !=
      null;

  Future<void> _startRuntimeIfNeeded() async {
    if (_runtimeStarted) {
      return;
    }
    final context = _sessionContext;
    if (context == null) {
      return;
    }
    final connectionId = context.connectionId;
    if (connectionId == null || !_hasActiveConnection(connectionId)) {
      await _enterDetachedMode(
        'Runtime detached from previous session. Transcript restored; reconnect to continue live.',
      );
      return;
    }

    final runtimeService = ref.read(aiRuntimeServiceProvider);
    if (runtimeService.hasActiveRunForSession(widget.sessionId)) {
      _runtimeStarted = true;
      return;
    }

    _runtimeStarted = true;
    try {
      await runtimeService.launch(
        AiRuntimeLaunchRequest(
          aiSessionId: widget.sessionId,
          connectionId: connectionId,
          provider: context.provider,
          executableOverride: context.executableOverride,
          remoteWorkingDirectory: context.remoteWorkingDirectory,
          structuredOutput:
              context.provider.capabilities.supportsStructuredOutput,
        ),
      );
      if (mounted) {
        setState(() {
          _runtimeAttachmentState = context.resumedSession
              ? _RuntimeAttachmentState.resumed
              : _RuntimeAttachmentState.attached;
        });
      }
      await ref
          .read(aiRepositoryProvider)
          .updateSessionStatus(sessionId: widget.sessionId, status: 'active');
    } on Exception catch (exception) {
      _runtimeStarted = false;
      await _insertTimelineEntry(
        role: 'error',
        message: 'Failed to start runtime: $exception',
      );
      await _enterDetachedMode(
        'Unable to launch runtime. Continue from transcript or reconnect.',
      );
    }
  }

  Future<void> _sendPrompt() async {
    final prompt = _promptController.text.trim();
    if (prompt.isEmpty || _sending) {
      return;
    }

    _promptController.clear();
    setState(() {
      _sending = true;
    });

    try {
      await _insertTimelineEntry(role: 'user', message: prompt);
      if (widget.autoStartRuntime &&
          _runtimeAttachmentState != _RuntimeAttachmentState.detached) {
        await _startRuntimeIfNeeded();
        if (_runtimeAttachmentState == _RuntimeAttachmentState.detached) {
          return;
        }
        await ref
            .read(aiRuntimeServiceProvider)
            .send(prompt, appendNewline: true, aiSessionId: widget.sessionId);
      } else {
        await _insertTimelineEntry(
          role: 'status',
          message:
              'Runtime is detached. Prompt saved to transcript until reconnect.',
        );
      }
    } on Exception catch (exception) {
      await _insertTimelineEntry(
        role: 'error',
        message: 'Unable to send prompt: $exception',
      );
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
        });
      }
    }
  }

  Future<void> _insertTimelineEntry({
    required String role,
    required String message,
    Map<String, dynamic>? metadata,
  }) async {
    final sessionMetadata = _sessionMetadata();
    final metadataPayload = <String, dynamic>{
      ...sessionMetadata,
      ...?metadata,
      'runtimeState': _runtimeAttachmentState.name,
    };
    await ref
        .read(aiRepositoryProvider)
        .insertTimelineEntry(
          AiTimelineEntriesCompanion.insert(
            sessionId: widget.sessionId,
            role: role,
            message: message,
            metadata: drift.Value(
              metadataPayload.isEmpty ? null : jsonEncode(metadataPayload),
            ),
          ),
        );
    _scrollToBottom();
  }

  Map<String, dynamic> _sessionMetadata() {
    final context = _sessionContext;
    if (context == null) {
      return const <String, dynamic>{};
    }
    return <String, dynamic>{
      'provider': context.provider.name,
      if (context.executableOverride != null)
        'executableOverride': context.executableOverride,
      'workingDirectory': context.remoteWorkingDirectory,
      'resumedSession': context.resumedSession,
      if (context.connectionId != null) 'connectionId': context.connectionId,
      if (context.hostId != null) 'hostId': context.hostId,
    };
  }

  Future<void> _enterDetachedMode(String message) async {
    if (mounted) {
      setState(() {
        _runtimeAttachmentState = _RuntimeAttachmentState.detached;
      });
    }
    await ref
        .read(aiRepositoryProvider)
        .updateSessionStatus(sessionId: widget.sessionId, status: 'detached');
    await _insertTimelineEntry(
      role: 'status',
      message: message,
      metadata: const <String, dynamic>{'runtimeState': 'detached'},
    );
  }

  Future<void> _reconnectRuntime() async {
    final context = _sessionContext;
    if (context == null || context.hostId == null) {
      _showSnackBar('Host metadata is missing; unable to reconnect runtime.');
      return;
    }

    setState(() {
      _reconnecting = true;
    });
    try {
      final result = await ref
          .read(activeSessionsProvider.notifier)
          .connect(context.hostId!);
      if (!result.success || result.connectionId == null) {
        _showSnackBar(result.error ?? 'Unable to reconnect runtime.');
        return;
      }

      final nextContext = context.copyWith(
        connectionId: result.connectionId,
        resumedSession: true,
      );
      setState(() {
        _sessionContext = nextContext;
        _runtimeStarted = false;
        _runtimeAttachmentState = _RuntimeAttachmentState.resumed;
      });
      await _insertTimelineEntry(
        role: 'status',
        message: 'Runtime reattached on a new SSH connection.',
        metadata: <String, dynamic>{
          'runtimeState': 'resumed',
          'connectionId': result.connectionId,
        },
      );
      await _startRuntimeIfNeeded();
    } finally {
      if (mounted) {
        setState(() {
          _reconnecting = false;
        });
      }
    }
  }

  void _handleRuntimeTimelineEvent(AiTimelineEvent timelineEvent) {
    if (timelineEvent.aiSessionId != widget.sessionId) {
      return;
    }
    if (timelineEvent.type == AiTimelineEventType.error) {
      _runtimeStarted = false;
    }

    if (timelineEvent.type == AiTimelineEventType.status) {
      final runtimeEventType = timelineEvent.metadata['runtimeEventType']
          ?.toString();
      if (runtimeEventType == AiRuntimeEventType.completed.name ||
          runtimeEventType == AiRuntimeEventType.cancelled.name) {
        _runtimeStarted = false;
      } else if (runtimeEventType == AiRuntimeEventType.started.name) {
        _runtimeStarted = true;
      }
    }

    final role = switch (timelineEvent.type) {
      AiTimelineEventType.message => 'assistant',
      AiTimelineEventType.tool => 'tool',
      AiTimelineEventType.thinking => 'thinking',
      AiTimelineEventType.status => 'status',
      AiTimelineEventType.error => 'error',
    };

    unawaited(
      _insertTimelineEntry(
        role: role,
        message: timelineEvent.message,
        metadata: <String, dynamic>{
          ...timelineEvent.metadata,
          'provider': timelineEvent.provider.name,
        },
      ),
    );
  }

  void _handleRuntimeTimelineStreamError(Object error, StackTrace stackTrace) {
    unawaited(
      _insertTimelineEntry(
        role: 'error',
        message: 'Runtime stream error: $error',
        metadata: <String, dynamic>{'stackTrace': stackTrace.toString()},
      ),
    );
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) {
      return;
    }
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
  }

  void _showSnackBar(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

/// Presentational tile for a single AI timeline entry.
class AiTimelineEntryTile extends StatelessWidget {
  /// Creates an [AiTimelineEntryTile].
  const AiTimelineEntryTile({required this.entry, super.key});

  /// Entry to render.
  final AiTimelineEntry entry;

  @override
  Widget build(BuildContext context) {
    final role = entry.role.toLowerCase();
    if (role == 'status') {
      return _StatusTimelineEntry(entry: entry);
    }
    if (role == 'tool' || role == 'thinking' || role == 'error') {
      return _SystemTimelineEntry(entry: entry, role: role);
    }
    final isUser = role == 'user';
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 700),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isUser
              ? Theme.of(context).colorScheme.primaryContainer
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          entry.message,
          style: TextStyle(
            color: isUser
                ? Theme.of(context).colorScheme.onPrimaryContainer
                : Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}

class _StatusTimelineEntry extends StatelessWidget {
  const _StatusTimelineEntry({required this.entry});

  final AiTimelineEntry entry;

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        entry.message,
        style: Theme.of(context).textTheme.labelMedium,
      ),
    ),
  );
}

class _SystemTimelineEntry extends StatelessWidget {
  const _SystemTimelineEntry({required this.entry, required this.role});

  final AiTimelineEntry entry;
  final String role;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final (icon, tint, background) = switch (role) {
      'tool' => (
        Icons.build_circle_outlined,
        colorScheme.secondary,
        colorScheme.secondaryContainer,
      ),
      'thinking' => (
        Icons.psychology_alt_outlined,
        colorScheme.tertiary,
        colorScheme.tertiaryContainer,
      ),
      'error' => (
        Icons.error_outline,
        colorScheme.error,
        colorScheme.errorContainer,
      ),
      _ => (
        Icons.info_outline,
        colorScheme.primary,
        colorScheme.primaryContainer,
      ),
    };

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      constraints: const BoxConstraints(maxWidth: 760),
      child: Card(
        color: background,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 18, color: tint),
              const SizedBox(width: 8),
              Expanded(
                child: Text(entry.message, style: TextStyle(color: tint)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final _aiTimelineProvider = StreamProvider.autoDispose
    .family<List<AiTimelineEntry>, int>(
      (ref, sessionId) =>
          ref.watch(aiRepositoryProvider).watchTimelineBySession(sessionId),
    );

class _AiSessionRuntimeContext {
  const _AiSessionRuntimeContext({
    required this.connectionId,
    required this.hostId,
    required this.provider,
    required this.executableOverride,
    required this.remoteWorkingDirectory,
    required this.resumedSession,
  });

  final int? connectionId;
  final int? hostId;
  final AiCliProvider provider;
  final String? executableOverride;
  final String remoteWorkingDirectory;
  final bool resumedSession;

  _AiSessionRuntimeContext copyWith({
    int? connectionId,
    int? hostId,
    AiCliProvider? provider,
    String? executableOverride,
    String? remoteWorkingDirectory,
    bool? resumedSession,
  }) => _AiSessionRuntimeContext(
    connectionId: connectionId ?? this.connectionId,
    hostId: hostId ?? this.hostId,
    provider: provider ?? this.provider,
    executableOverride: executableOverride ?? this.executableOverride,
    remoteWorkingDirectory:
        remoteWorkingDirectory ?? this.remoteWorkingDirectory,
    resumedSession: resumedSession ?? this.resumedSession,
  );
}

enum _RuntimeAttachmentState { restoring, attached, resumed, detached }
