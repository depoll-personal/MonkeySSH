import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/database.dart';
import '../../data/repositories/ai_repository.dart';
import '../../domain/models/ai_cli_provider.dart';
import '../../domain/services/acp_client.dart';
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
  static const List<String> _steeringSlashCommands = <String>[
    '/steer',
    '/steer-list',
    '/steer-clear',
  ];
  static final RegExp _slashCommandPattern = RegExp(
    r'(^|[\s(,])\/([a-z][a-z0-9_-]*)(?=\s|$)',
    multiLine: true,
  );

  late final TextEditingController _promptController;
  late final FocusNode _promptFocusNode;
  late final ScrollController _scrollController;
  late AiComposerAutocompleteEngine _composerAutocompleteEngine;

  StreamSubscription<AiTimelineEvent>? _runtimeTimelineSubscription;
  StreamSubscription<AcpEvent>? _acpEventSubscription;
  Future<List<String>>? _remoteFileSuggestionsInFlight;
  List<String>? _cachedRemoteFileSuggestions;
  List<AiComposerSuggestion> _composerSuggestions =
      const <AiComposerSuggestion>[];
  var _selectedComposerSuggestionIndex = 0;
  var _composerSuggestionRevision = 0;
  _AiSessionRuntimeContext? _sessionContext;
  AcpClient? _acpClient;
  AcpSession? _acpSession;
  bool _acpUnavailableForSession = false;
  String? _savedAcpModelId;
  final List<String> _steeringPromptQueue = <String>[];
  List<String> _availableSlashCommands = const <String>[];

  /// Buffers for aggregating streaming ACP chunks into single timeline entries.
  final StringBuffer _acpMessageBuffer = StringBuffer();
  final StringBuffer _acpThoughtBuffer = StringBuffer();
  int? _acpMessageEntryId;
  int? _acpThoughtEntryId;
  var _acpMessageInsertPending = false;
  var _acpThoughtInsertPending = false;

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
    _availableSlashCommands = _baseSlashCommands(
      widget.provider ?? AiCliProvider.claude,
    );
    _composerAutocompleteEngine = AiComposerAutocompleteEngine(
      slashCommands: _availableSlashCommands,
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
    unawaited(_disposeAcpClientState());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final timelineAsync = ref.watch(_aiTimelineProvider(widget.sessionId));
    final timelineEntries = timelineAsync.asData?.value;
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

    final acpSession = _acpSession;
    final isAcp = acpSession != null;
    final displayLabel = isAcp
        ? 'ACP · ${acpSession.currentModelId ?? executableLabel}'
        : executableLabel;
    final modelLabel = _currentModelLabel(
      acpSession: acpSession,
      entries: timelineEntries,
    );
    final modeLabel = _currentModeLabel(
      acpSession: acpSession,
      entries: timelineEntries,
    );
    final contextLabel = _contextRemainingLabel(entries: timelineEntries);

    return Scaffold(
      appBar: AppBar(
        title: Text('AI Session #${widget.sessionId}'),
        actions: [
          if (isAcp && acpSession.availableModels.length > 1)
            PopupMenuButton<String>(
              icon: const Icon(Icons.model_training, size: 20),
              tooltip: 'Select model',
              onSelected: (modelId) {
                setState(() {
                  _acpSession = AcpSession(
                    sessionId: acpSession.sessionId,
                    availableModels: acpSession.availableModels,
                    currentModelId: modelId,
                    availableModes: acpSession.availableModes,
                    currentModeId: acpSession.currentModeId,
                  );
                });
                unawaited(
                  _persistTimelineEntrySafely(
                    role: 'status',
                    message: 'Model changed to $modelId',
                    metadata: <String, dynamic>{'acpModelId': modelId},
                  ),
                );
              },
              itemBuilder: (context) => acpSession.availableModels
                  .map(
                    (model) => PopupMenuItem<String>(
                      value: model.modelId,
                      child: Row(
                        children: [
                          if (model.modelId == acpSession.currentModelId)
                            Icon(
                              Icons.check,
                              size: 16,
                              color: theme.colorScheme.primary,
                            )
                          else
                            const SizedBox(width: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              model.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.memory_outlined,
                      size: 14,
                      color: theme.hintColor,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '$displayLabel · $workingDirectory',
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
                const SizedBox(height: 4),
                Text(
                  'Model: $modelLabel · $contextLabel · Mode: $modeLabel',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall,
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
              child: SelectionArea(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 920),
                    child: timelineAsync.when(
                      loading: () => const Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      error: (error, _) => Center(
                        child: Text('Failed to load timeline: $error'),
                      ),
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
            ),
            _buildComposer(context),
          ],
        ),
      ),
    );
  }

  String _currentModelLabel({
    required AcpSession? acpSession,
    required List<AiTimelineEntry>? entries,
  }) {
    final selectedModel = acpSession?.currentModelId ?? _savedAcpModelId;
    if (selectedModel != null && selectedModel.isNotEmpty) {
      return selectedModel;
    }
    final telemetry = _latestCliTelemetry(entries: entries);
    return telemetry.model ?? '--';
  }

  String _currentModeLabel({
    required AcpSession? acpSession,
    required List<AiTimelineEntry>? entries,
  }) {
    if (acpSession != null) {
      final mode = acpSession.currentModeId;
      if (mode != null && mode.isNotEmpty) {
        return mode;
      }
      return 'acp';
    }
    final telemetry = _latestCliTelemetry(entries: entries);
    return telemetry.mode ?? '--';
  }

  String _contextRemainingLabel({required List<AiTimelineEntry>? entries}) {
    final telemetry = _latestCliTelemetry(entries: entries);
    if (telemetry.contextRemainingTokens != null) {
      return 'Context: ${telemetry.contextRemainingTokens} tok left';
    }
    if (telemetry.contextUsedTokens != null) {
      return 'Context: ${telemetry.contextUsedTokens} tok used';
    }
    return 'Context: --';
  }

  _CliRuntimeTelemetry _latestCliTelemetry({
    required List<AiTimelineEntry>? entries,
  }) {
    if (entries == null || entries.isEmpty) {
      return const _CliRuntimeTelemetry();
    }
    String? model;
    String? mode;
    int? contextRemainingTokens;
    int? contextUsedTokens;
    for (final entry in entries.reversed) {
      final metadata = AiSessionMetadata.decode(entry.metadata);
      final payload = _metadataMap(metadata['payload']);
      model ??= _firstNonEmptyString(<String?>[
        AiSessionMetadata.readString(metadata, 'currentModelId'),
        AiSessionMetadata.readString(metadata, 'acpModelId'),
        _firstNonEmptyString(<String?>[
          _stringValue(payload?['model']),
          _stringValue(payload?['modelId']),
          _stringValue(payload?['currentModelId']),
          _stringValue(_metadataMap(payload?['message'])?['model']),
        ]),
      ]);
      mode ??= _firstNonEmptyString(<String?>[
        AiSessionMetadata.readString(metadata, 'currentModeId'),
        _firstNonEmptyString(<String?>[
          _stringValue(payload?['mode']),
          _stringValue(payload?['modeId']),
          _stringValue(payload?['currentModeId']),
        ]),
      ]);
      final usage = _metadataMap(
        payload?['usage'] ?? _metadataMap(payload?['message'])?['usage'],
      );
      contextRemainingTokens ??= _firstNonNullInt(<int?>[
        _intValue(usage?['context_window_remaining']),
        _intValue(usage?['remaining_context_tokens']),
        _intValue(usage?['remainingTokens']),
        _intValue(payload?['contextRemainingTokens']),
      ]);
      contextUsedTokens ??= _firstNonNullInt(<int?>[
        _intValue(usage?['total_tokens']),
        _sumInts(
          _intValue(usage?['input_tokens']),
          _intValue(usage?['output_tokens']),
        ),
      ]);
      if (model != null &&
          mode != null &&
          (contextRemainingTokens != null || contextUsedTokens != null)) {
        break;
      }
    }
    return _CliRuntimeTelemetry(
      model: model,
      mode: mode,
      contextRemainingTokens: contextRemainingTokens,
      contextUsedTokens: contextUsedTokens,
    );
  }

  Map<String, dynamic>? _metadataMap(Object? value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map<Object?, Object?>) {
      return value.map((key, mapValue) => MapEntry(key.toString(), mapValue));
    }
    return null;
  }

  String? _stringValue(Object? value) {
    if (value is! String) {
      return null;
    }
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  int? _intValue(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value.trim());
    }
    return null;
  }

  int? _sumInts(int? left, int? right) {
    if (left == null && right == null) {
      return null;
    }
    return (left ?? 0) + (right ?? 0);
  }

  int? _firstNonNullInt(List<int?> values) {
    for (final value in values) {
      if (value != null) {
        return value;
      }
    }
    return null;
  }

  String? _firstNonEmptyString(List<String?> values) {
    for (final value in values) {
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }
    return null;
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
                    onPressed: _sending || _sessionContext == null
                        ? null
                        : () => unawaited(_sendPrompt()),
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

    final remoteDir = context.remoteWorkingDirectory;
    final cdDirectory = remoteDir.startsWith('~')
        ? remoteDir
        : shellEscape(remoteDir);
    final process = await session.execute(
      'cd $cdDirectory && '
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
        _availableSlashCommands = _baseSlashCommands(context.provider);
        _composerAutocompleteEngine = AiComposerAutocompleteEngine(
          slashCommands: _availableSlashCommands,
        );
      });
      unawaited(_loadProviderSlashCommands(context));
      if (widget.autoStartRuntime &&
          context.provider.capabilities.autoStartRuntime) {
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
    final latestEntry = await repository.getLatestTimelineEntry(
      widget.sessionId,
    );
    final latestMetadata = latestEntry == null
        ? const <String, dynamic>{}
        : AiSessionMetadata.decode(latestEntry.metadata);

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

    // Restore the last-used ACP model selection.
    _savedAcpModelId =
        AiSessionMetadata.readString(latestMetadata, 'acpModelId') ??
        AiSessionMetadata.readString(latestMetadata, 'currentModelId');

    return _AiSessionRuntimeContext(
      connectionId: connectionId,
      hostId: hostId,
      provider: provider,
      executableOverride: executableOverride,
      remoteWorkingDirectory: remoteWorkingDirectory,
      resumedSession: widget.isResumeRequest || widget.connectionId == null,
    );
  }

  List<String> _baseSlashCommands(AiCliProvider provider) {
    final commands = LinkedHashSet<String>.from(
      provider.capabilities.composerSlashCommands,
    );
    if (provider.capabilities.supportsSteeringPrompts) {
      commands.addAll(_steeringSlashCommands);
    }
    return commands.toList(growable: false);
  }

  Future<void> _loadProviderSlashCommands(
    _AiSessionRuntimeContext context,
  ) async {
    final discovered = await _discoverSlashCommandsFromCli(context);
    if (!mounted || discovered.isEmpty) {
      return;
    }
    final merged = LinkedHashSet<String>.from(
      _baseSlashCommands(context.provider),
    )..addAll(discovered);
    final nextCommands = merged.toList(growable: false);
    if (_listsEqual(_availableSlashCommands, nextCommands)) {
      return;
    }
    setState(() {
      _availableSlashCommands = nextCommands;
      _composerAutocompleteEngine = AiComposerAutocompleteEngine(
        slashCommands: _availableSlashCommands,
      );
    });
    await _refreshComposerSuggestions();
  }

  Future<List<String>> _discoverSlashCommandsFromCli(
    _AiSessionRuntimeContext context,
  ) async {
    final connectionId = context.connectionId;
    if (connectionId == null) {
      return const <String>[];
    }
    final session = ref
        .read(activeSessionsProvider.notifier)
        .getSession(connectionId);
    if (session == null) {
      return const <String>[];
    }

    final executable =
        (context.executableOverride ?? context.provider.executable).trim();
    if (executable.isEmpty) {
      return const <String>[];
    }

    final probeCommands = _slashCommandProbeCommands(
      context: context,
      executable: executable,
    );
    if (probeCommands.isEmpty) {
      return const <String>[];
    }
    final discovered = <String>{};
    for (final probeCommand in probeCommands) {
      final process = await session.execute(
        'sh -lc ${shellEscape('$probeCommand 2>&1')}',
      );
      final output = await process.stdout
          .cast<List<int>>()
          .transform(utf8.decoder)
          .join();
      await process.done;
      for (final match in _slashCommandPattern.allMatches(output)) {
        final command = match.group(2);
        if (command == null || command.isEmpty) {
          continue;
        }
        discovered.add('/$command');
      }
    }
    return discovered.toList(growable: false);
  }

  List<String> _slashCommandProbeCommands({
    required _AiSessionRuntimeContext context,
    required String executable,
  }) {
    final helpPrompt = shellEscape('/help');
    return switch (context.provider) {
      AiCliProvider.claude => <String>[
        '$executable --print --max-turns 1 $helpPrompt',
      ],
      AiCliProvider.codex => <String>['$executable $helpPrompt'],
      AiCliProvider.opencode => <String>['$executable run $helpPrompt'],
      AiCliProvider.copilot => <String>[
        '$executable -p $helpPrompt --resume ${shellEscape(_copilotResumeSessionId(widget.sessionId))}',
      ],
      AiCliProvider.gemini => <String>['$executable $helpPrompt'],
      AiCliProvider.acp => const <String>[],
    };
  }

  bool _listsEqual(List<String> a, List<String> b) {
    if (identical(a, b)) {
      return true;
    }
    if (a.length != b.length) {
      return false;
    }
    for (var index = 0; index < a.length; index++) {
      if (a[index] != b[index]) {
        return false;
      }
    }
    return true;
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

  bool _prefersAcpTransport(AiCliProvider provider) => switch (provider) {
    AiCliProvider.claude ||
    AiCliProvider.codex ||
    AiCliProvider.opencode ||
    AiCliProvider.copilot ||
    AiCliProvider.gemini ||
    AiCliProvider.acp => true,
  };

  bool _requiresAcpTransport(AiCliProvider provider) =>
      provider == AiCliProvider.acp;

  Future<void> _launchAdapterRuntime({
    required _AiSessionRuntimeContext context,
    required int connectionId,
  }) async {
    await ref
        .read(aiRuntimeServiceProvider)
        .launch(
          AiRuntimeLaunchRequest(
            aiSessionId: widget.sessionId,
            connectionId: connectionId,
            provider: context.provider,
            executableOverride: context.executableOverride,
            remoteWorkingDirectory: context.remoteWorkingDirectory,
          ),
        );
  }

  Future<void> _startRuntimeIfNeeded({bool force = false}) async {
    final runtimeService = ref.read(aiRuntimeServiceProvider);
    final context = _sessionContext;
    if (context == null) {
      return;
    }
    if (!force && !context.provider.capabilities.autoStartRuntime) {
      return;
    }
    final connectionId = context.connectionId;
    if (connectionId == null || !_hasActiveConnection(connectionId)) {
      await _enterDetachedMode(
        'Runtime detached from previous session. Transcript restored; reconnect to continue live.',
      );
      return;
    }

    final useAcp = _prefersAcpTransport(context.provider);
    final requiresAcp = _requiresAcpTransport(context.provider);
    final hasActiveRun = runtimeService.hasActiveRunForSession(
      widget.sessionId,
    );
    if ((_runtimeStarted && hasActiveRun) || hasActiveRun) {
      _runtimeStarted = true;
      if (mounted) {
        setState(() {
          _runtimeAttachmentState = context.resumedSession
              ? _RuntimeAttachmentState.resumed
              : _RuntimeAttachmentState.attached;
        });
      }
      if (useAcp && _acpClient == null && !_acpUnavailableForSession) {
        final acpReady = await _initializeAcpClient(
          context,
          emitFailure: requiresAcp,
        );
        if (acpReady) {
          _acpUnavailableForSession = false;
        }
        if (!acpReady && !requiresAcp) {
          _acpUnavailableForSession = true;
          await _insertTimelineEntry(
            role: 'status',
            message:
                'ACP unavailable for ${context.provider.executable}; using provider adapter mode.',
          );
        }
      }
      return;
    }
    if (_runtimeStarted) {
      _runtimeStarted = false;
    }

    _runtimeStarted = true;
    _acpUnavailableForSession = false;
    try {
      await runtimeService.launch(
        AiRuntimeLaunchRequest(
          aiSessionId: widget.sessionId,
          connectionId: connectionId,
          provider: context.provider,
          executableOverride: context.executableOverride,
          remoteWorkingDirectory: context.remoteWorkingDirectory,
          structuredOutput:
              !useAcp && context.provider.capabilities.supportsStructuredOutput,
          acpMode: useAcp,
        ),
      );

      if (mounted) {
        setState(() {
          _runtimeAttachmentState = context.resumedSession
              ? _RuntimeAttachmentState.resumed
              : _RuntimeAttachmentState.attached;
        });
      }
      if (useAcp) {
        final acpReady = await _initializeAcpClient(
          context,
          emitFailure: requiresAcp,
        );
        if (acpReady) {
          _acpUnavailableForSession = false;
        }
        if (!acpReady && !requiresAcp) {
          _acpUnavailableForSession = true;
          await runtimeService.cancel(aiSessionId: widget.sessionId);
          await _launchAdapterRuntime(
            context: context,
            connectionId: connectionId,
          );
          await _insertTimelineEntry(
            role: 'status',
            message:
                'ACP unavailable for ${context.provider.executable}; switched to provider adapter mode.',
          );
        }
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

  Future<void> _disposeAcpClientState() async {
    await _acpEventSubscription?.cancel();
    _acpEventSubscription = null;
    final client = _acpClient;
    _acpClient = null;
    _acpSession = null;
    if (client != null) {
      await client.dispose();
    }
  }

  Future<bool> _initializeAcpClient(
    _AiSessionRuntimeContext context, {
    bool emitFailure = true,
  }) async {
    await _disposeAcpClientState();
    final runtimeService = ref.read(aiRuntimeServiceProvider);
    final process = runtimeService.getActiveProcess(widget.sessionId);
    if (process == null) {
      if (emitFailure) {
        await _insertTimelineEntry(
          role: 'error',
          message: 'ACP process not available after launch.',
        );
      }
      return false;
    }
    final client = AcpClient(process: process);
    _acpClient = client;
    _acpEventSubscription = client.events.listen(
      _handleAcpEvent,
      onError: (Object error) {
        unawaited(
          _persistTimelineEntrySafely(
            role: 'error',
            message: 'ACP stream error: $error',
          ),
        );
      },
    );
    try {
      final initResult = await client.initialize().timeout(
        const Duration(seconds: 6),
      );
      final agentInfo = client.agentInfo;
      await _insertTimelineEntry(
        role: 'status',
        message:
            'ACP initialized: ${agentInfo?.title ?? agentInfo?.name ?? 'Agent'}'
            '${agentInfo?.version != null ? ' v${agentInfo!.version}' : ''}',
        metadata: <String, dynamic>{'acpInitialize': initResult},
      );
      final session = await client
          .createSession(cwd: await _resolveAcpSessionCwd(context))
          .timeout(const Duration(seconds: 6));
      // Restore previously selected model if persisted.
      final savedModelId = _savedAcpModelId;
      if (savedModelId != null &&
          session.availableModels.any((m) => m.modelId == savedModelId)) {
        _acpSession = AcpSession(
          sessionId: session.sessionId,
          availableModels: session.availableModels,
          currentModelId: savedModelId,
          availableModes: session.availableModes,
          currentModeId: session.currentModeId,
        );
      } else {
        _acpSession = session;
      }
      if (session.availableModels.isNotEmpty) {
        await _insertTimelineEntry(
          role: 'status',
          message:
              'Session created · model: ${session.currentModelId ?? 'default'} · '
              '${session.availableModels.length} models available',
          metadata: <String, dynamic>{
            'acpSessionId': session.sessionId,
            'currentModelId': session.currentModelId,
            'availableModels': session.availableModels
                .map((m) => m.modelId)
                .toList(),
          },
        );
      }
      _acpUnavailableForSession = false;
      return true;
    } on AcpClientException catch (error) {
      if (emitFailure) {
        final isCopilot = context.provider == AiCliProvider.copilot;
        await _insertTimelineEntry(
          role: 'error',
          message:
              'ACP initialization failed: $error\n\n'
              '${isCopilot ? 'If this is Copilot, run `copilot login` on the remote host first.\n\n' : ''}'
              'Make sure the CLI is installed and in your PATH on the remote host.',
          metadata: <String, dynamic>{
            if (error.code != null) 'acpErrorCode': error.code,
            if (error.data != null) 'acpErrorData': error.data,
            'provider': context.provider.name,
            if (context.executableOverride != null)
              'executableOverride': context.executableOverride,
          },
        );
      }
    } on TimeoutException catch (error) {
      if (emitFailure) {
        await _insertTimelineEntry(
          role: 'error',
          message: 'ACP initialization timed out: $error',
          metadata: <String, dynamic>{'provider': context.provider.name},
        );
      }
    } on Exception catch (error) {
      if (emitFailure) {
        await _insertTimelineEntry(
          role: 'error',
          message: 'ACP initialization failed: $error',
          metadata: <String, dynamic>{'provider': context.provider.name},
        );
      }
    }
    await _disposeAcpClientState();
    return false;
  }

  Future<String> _resolveAcpSessionCwd(_AiSessionRuntimeContext context) async {
    final absoluteCwd = _acpSessionCwd(context.remoteWorkingDirectory);
    if (absoluteCwd != null) {
      return absoluteCwd;
    }
    final connectionId = context.connectionId;
    if (connectionId == null) {
      return '/';
    }
    final session = ref
        .read(activeSessionsProvider.notifier)
        .getSession(connectionId);
    if (session == null) {
      return '/';
    }
    final remoteDir = context.remoteWorkingDirectory.trim();
    final cdDirectory = remoteDir.startsWith('~')
        ? remoteDir
        : shellEscape(remoteDir);
    final process = await session.execute(
      'cd $cdDirectory >/dev/null 2>&1 && pwd -P',
    );
    final output = await process.stdout
        .cast<List<int>>()
        .transform(utf8.decoder)
        .join();
    await process.done;
    String? resolved;
    for (final line in output.split('\n')) {
      final trimmedLine = line.trim();
      if (trimmedLine.isNotEmpty) {
        resolved = trimmedLine;
      }
    }
    return resolved != null && resolved.startsWith('/') ? resolved : '/';
  }

  String? _acpSessionCwd(String remoteWorkingDirectory) {
    final trimmed = remoteWorkingDirectory.trim();
    if (trimmed.startsWith('/')) {
      return trimmed;
    }
    return null;
  }

  Future<void> _sendPrompt() async {
    final prompt = _promptController.text.trim();
    if (prompt.isEmpty || _sending) {
      return;
    }
    final context = _sessionContext;
    if (context == null) {
      await _insertTimelineEntry(
        role: 'status',
        message: 'Session is still loading. Please try again in a moment.',
      );
      return;
    }

    if (await _handleSteeringComposerCommand(
      prompt: prompt,
      context: context,
    )) {
      _promptController.clear();
      return;
    }
    final appliedSteeringPrompts = _steeringPromptQueue.length;
    _promptController.clear();
    setState(() {
      _sending = true;
    });

    try {
      await _insertTimelineEntry(
        role: 'user',
        message: prompt,
        metadata: appliedSteeringPrompts > 0
            ? <String, dynamic>{'steeringPromptCount': appliedSteeringPrompts}
            : null,
      );
      if (context.provider == AiCliProvider.claude) {
        await _runClaudePrompt(prompt: prompt, context: context);
        return;
      }
      if (context.provider == AiCliProvider.codex) {
        await _runCodexPrompt(prompt: prompt, context: context);
        return;
      }
      if (context.provider == AiCliProvider.opencode) {
        await _runOpenCodePrompt(prompt: prompt, context: context);
        return;
      }
      if (widget.autoStartRuntime &&
          _runtimeAttachmentState != _RuntimeAttachmentState.detached) {
        await _startRuntimeIfNeeded(force: true);
        if (_runtimeAttachmentState == _RuntimeAttachmentState.detached) {
          return;
        }

        // Use ACP protocol when available.
        final acpClient = _acpClient;
        final acpSession = _acpSession;
        if (acpClient != null && acpSession != null) {
          await _sendAcpPrompt(
            client: acpClient,
            sessionId: acpSession.sessionId,
            prompt: prompt,
          );
          return;
        }
        if (context.provider == AiCliProvider.acp) {
          await _insertTimelineEntry(
            role: 'error',
            message:
                'ACP session is not ready. Reconnect runtime and ensure the provider is authenticated.',
          );
          return;
        }

        // Legacy: copilot one-shot mode.
        if (context.provider == AiCliProvider.copilot) {
          await _runCopilotPrompt(prompt: prompt, context: context);
          return;
        }

        // Legacy: raw stdin mode for non-ACP providers.
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

  Future<bool> _handleSteeringComposerCommand({
    required String prompt,
    required _AiSessionRuntimeContext context,
  }) async {
    final isSteeringCommand =
        prompt == '/steer-list' ||
        prompt == '/steer-clear' ||
        prompt.startsWith('/steer');
    if (!context.provider.capabilities.supportsSteeringPrompts) {
      if (isSteeringCommand) {
        await _insertTimelineEntry(
          role: 'status',
          message:
              'Steering queue is not supported for ${context.provider.executable}.',
        );
        return true;
      }
      return false;
    }
    if (prompt == '/steer-list') {
      final message = _steeringPromptQueue.isEmpty
          ? 'No queued steering prompts.'
          : 'Steering prompts (${_steeringPromptQueue.length}):\n'
                '${_steeringPromptQueue.asMap().entries.map((entry) => '${entry.key + 1}. ${entry.value}').join('\n')}';
      await _insertTimelineEntry(role: 'status', message: message);
      return true;
    }
    if (prompt == '/steer-clear') {
      _steeringPromptQueue.clear();
      await _insertTimelineEntry(
        role: 'status',
        message: 'Cleared queued steering prompts.',
      );
      return true;
    }
    if (prompt.startsWith('/steer')) {
      final steeringPrompt = prompt.substring('/steer'.length).trim();
      if (steeringPrompt.isEmpty) {
        await _insertTimelineEntry(
          role: 'status',
          message:
              'Usage: /steer <instruction>. Use /steer-list to view queued prompts.',
        );
        return true;
      }
      _steeringPromptQueue.add(steeringPrompt);
      await _insertTimelineEntry(
        role: 'status',
        message: 'Queued steering prompt #${_steeringPromptQueue.length}.',
        metadata: <String, dynamic>{
          'steeringPrompt': steeringPrompt,
          'steeringPromptCount': _steeringPromptQueue.length,
        },
      );
      return true;
    }
    return false;
  }

  String? _nativeSteeringCommand(AiCliProvider provider) => switch (provider) {
    AiCliProvider.claude ||
    AiCliProvider.codex ||
    AiCliProvider.opencode => '/steer',
    AiCliProvider.copilot || AiCliProvider.gemini || AiCliProvider.acp => null,
  };

  Future<void> _applyQueuedNativeSteering(
    _AiSessionRuntimeContext context,
  ) async {
    if (_steeringPromptQueue.isEmpty) {
      return;
    }
    final command = _nativeSteeringCommand(context.provider);
    if (command == null) {
      return;
    }
    final runtimeService = ref.read(aiRuntimeServiceProvider);
    final queuedPrompts = List<String>.from(_steeringPromptQueue);
    for (final steeringPrompt in queuedPrompts) {
      await runtimeService.send(
        '$command $steeringPrompt',
        appendNewline: true,
        aiSessionId: widget.sessionId,
      );
    }
    _steeringPromptQueue.clear();
    await _insertTimelineEntry(
      role: 'status',
      message:
          'Applied ${queuedPrompts.length} queued steering prompt${queuedPrompts.length == 1 ? '' : 's'}.',
    );
  }

  Future<void> _sendAcpPrompt({
    required AcpClient client,
    required String sessionId,
    required String prompt,
  }) async {
    // Reset streaming buffers for the new turn.
    _flushAcpBuffers();
    try {
      final result = await client.sendPrompt(
        sessionId: sessionId,
        text: prompt,
        modelId: _acpSession?.currentModelId,
      );
      final stopReason = result['stopReason']?.toString();
      if (stopReason != null && stopReason != 'end_turn') {
        await _insertTimelineEntry(
          role: 'status',
          message: 'Turn ended: $stopReason',
        );
      }
    } on AcpClientException catch (error) {
      await _insertTimelineEntry(
        role: 'error',
        message: 'ACP prompt error: $error',
      );
    }
  }

  void _handleAcpEvent(AcpEvent event) {
    switch (event.type) {
      case AcpEventType.agentMessage:
        _appendAcpChunk(
          buffer: _acpMessageBuffer,
          entryIdGetter: () => _acpMessageEntryId,
          entryIdSetter: (id) => _acpMessageEntryId = id,
          insertPendingGetter: () => _acpMessageInsertPending,
          insertPendingSetter: ({required pending}) =>
              _acpMessageInsertPending = pending,
          role: 'assistant',
          text: event.text,
        );
      case AcpEventType.agentThought:
        _appendAcpChunk(
          buffer: _acpThoughtBuffer,
          entryIdGetter: () => _acpThoughtEntryId,
          entryIdSetter: (id) => _acpThoughtEntryId = id,
          insertPendingGetter: () => _acpThoughtInsertPending,
          insertPendingSetter: ({required pending}) =>
              _acpThoughtInsertPending = pending,
          role: 'thinking',
          text: event.text,
        );
      case AcpEventType.toolCall:
        // Flush any open message/thought buffers before a tool call.
        _flushAcpBuffers();
        final metadata = <String, dynamic>{
          'acpEventType': event.type.name,
          if (event.toolCallId != null) 'toolCallId': event.toolCallId,
        };
        final update = event.rawUpdate;
        final title = update['title']?.toString();
        final kind = update['kind']?.toString();
        if (title != null) {
          metadata['toolName'] = title;
        }
        if (kind != null) {
          metadata['toolKind'] = kind;
        }
        final rawInput = update['rawInput'];
        if (rawInput != null) {
          metadata['input'] = rawInput;
        }
        final locations = update['locations'];
        if (locations is List<dynamic>) {
          metadata['locations'] = locations;
        }
        unawaited(
          _persistTimelineEntrySafely(
            role: 'tool',
            message: event.text,
            metadata: metadata,
          ),
        );
      case AcpEventType.toolCallUpdate:
        final metadata = <String, dynamic>{
          'acpEventType': event.type.name,
          if (event.toolCallId != null) 'toolCallId': event.toolCallId,
        };
        final update = event.rawUpdate;
        final title = update['title']?.toString();
        final kind = update['kind']?.toString();
        if (title != null) {
          metadata['toolName'] = title;
        }
        if (kind != null) {
          metadata['toolKind'] = kind;
        }
        final status = update['status']?.toString();
        if (status != null) {
          metadata['toolStatus'] = status;
        }
        final rawInput = update['rawInput'];
        if (rawInput != null) {
          metadata['input'] = rawInput;
        }
        final rawOutput = update['rawOutput'];
        if (rawOutput != null) {
          metadata['output'] = rawOutput;
        }
        unawaited(
          _persistTimelineEntrySafely(
            role: 'tool',
            message: event.text,
            metadata: metadata,
          ),
        );
      case AcpEventType.unknown:
        unawaited(
          _persistTimelineEntrySafely(
            role: 'status',
            message: event.text,
            metadata: <String, dynamic>{
              'acpEventType': event.type.name,
              'payload': event.rawUpdate,
            },
          ),
        );
    }
  }

  /// Appends a streaming chunk to [buffer] and creates or updates
  /// the corresponding timeline entry.
  void _appendAcpChunk({
    required StringBuffer buffer,
    required int? Function() entryIdGetter,
    required void Function(int) entryIdSetter,
    required bool Function() insertPendingGetter,
    required void Function({required bool pending}) insertPendingSetter,
    required String role,
    required String text,
  }) {
    buffer.write(text);
    final entryId = entryIdGetter();
    if (entryId != null) {
      // Update the existing entry with accumulated text.
      unawaited(
        ref
            .read(aiRepositoryProvider)
            .updateTimelineEntryMessage(entryId, buffer.toString()),
      );
    } else {
      if (insertPendingGetter()) {
        return;
      }
      insertPendingSetter(pending: true);
      // Create the initial entry — the first chunk.
      unawaited(
        _insertTimelineEntry(role: role, message: buffer.toString())
            .then((insertedId) async {
              if (insertedId != null) {
                entryIdSetter(insertedId);
                await ref
                    .read(aiRepositoryProvider)
                    .updateTimelineEntryMessage(insertedId, buffer.toString());
              }
            })
            .whenComplete(() => insertPendingSetter(pending: false)),
      );
    }
  }

  /// Resets streaming buffers between turns (e.g., before tool calls or
  /// at end of turn).
  void _flushAcpBuffers() {
    _acpMessageBuffer.clear();
    _acpMessageEntryId = null;
    _acpMessageInsertPending = false;
    _acpThoughtBuffer.clear();
    _acpThoughtEntryId = null;
    _acpThoughtInsertPending = false;
  }

  Future<void> _runClaudePrompt({
    required String prompt,
    required _AiSessionRuntimeContext context,
  }) async {
    await _runProviderPrompt(prompt: prompt, context: context);
  }

  Future<void> _runCodexPrompt({
    required String prompt,
    required _AiSessionRuntimeContext context,
  }) async {
    await _runProviderPrompt(prompt: prompt, context: context);
  }

  Future<void> _runOpenCodePrompt({
    required String prompt,
    required _AiSessionRuntimeContext context,
  }) async {
    await _runProviderPrompt(prompt: prompt, context: context);
  }

  Future<void> _runProviderPrompt({
    required String prompt,
    required _AiSessionRuntimeContext context,
  }) async {
    if (widget.autoStartRuntime &&
        _runtimeAttachmentState != _RuntimeAttachmentState.detached) {
      await _startRuntimeIfNeeded(force: true);
      if (_runtimeAttachmentState == _RuntimeAttachmentState.detached) {
        return;
      }
      await _applyQueuedNativeSteering(context);
      final acpClient = _acpClient;
      final acpSession = _acpSession;
      if (acpClient != null && acpSession != null) {
        await _sendAcpPrompt(
          client: acpClient,
          sessionId: acpSession.sessionId,
          prompt: prompt,
        );
        return;
      }
      await ref
          .read(aiRuntimeServiceProvider)
          .send(prompt, appendNewline: true, aiSessionId: widget.sessionId);
      return;
    }
    await _insertTimelineEntry(
      role: 'status',
      message:
          'Runtime is detached. Prompt saved to transcript until reconnect.',
    );
  }

  Future<void> _runOneShotPrompt({
    required _AiSessionRuntimeContext context,
    required String inFlightMessage,
    required List<String> extraArguments,
    bool structuredOutput = false,
  }) async {
    final connectionId = context.connectionId;
    if (connectionId == null || !_hasActiveConnection(connectionId)) {
      await _enterDetachedMode(
        'Runtime detached from previous session. Transcript restored; reconnect to continue live.',
      );
      return;
    }
    final runtimeService = ref.read(aiRuntimeServiceProvider);
    if (runtimeService.hasActiveRunForSession(widget.sessionId)) {
      try {
        await runtimeService.cancel(aiSessionId: widget.sessionId);
        await Future<void>.delayed(const Duration(milliseconds: 120));
      } on Exception {
        // Best effort stale-runtime cleanup.
      }
    }
    if (runtimeService.hasActiveRunForSession(widget.sessionId)) {
      await _insertTimelineEntry(role: 'status', message: inFlightMessage);
      return;
    }
    await runtimeService.launch(
      AiRuntimeLaunchRequest(
        aiSessionId: widget.sessionId,
        connectionId: connectionId,
        provider: context.provider,
        executableOverride: context.executableOverride,
        remoteWorkingDirectory: context.remoteWorkingDirectory,
        structuredOutput: structuredOutput,
        extraArguments: extraArguments,
      ),
    );
  }

  Future<void> _runCopilotPrompt({
    required String prompt,
    required _AiSessionRuntimeContext context,
  }) async {
    await _runOneShotPrompt(
      context: context,
      inFlightMessage: 'Previous Copilot request is still running.',
      structuredOutput: context.provider.capabilities.supportsStructuredOutput,
      extraArguments: <String>[
        '-p',
        prompt,
        '--resume',
        _copilotResumeSessionId(widget.sessionId),
      ],
    );
  }

  String _copilotResumeSessionId(int aiSessionId) {
    final hex = aiSessionId.toRadixString(16).toLowerCase();
    final suffix = hex.length > 12
        ? hex.substring(hex.length - 12)
        : hex.padLeft(12, '0');
    return '00000000-0000-4000-8000-$suffix';
  }

  Future<int?> _insertTimelineEntry({
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
    final encodedMetadata = _encodeTimelineMetadata(metadataPayload);
    final insertedId = await ref
        .read(aiRepositoryProvider)
        .insertTimelineEntry(
          AiTimelineEntriesCompanion.insert(
            sessionId: widget.sessionId,
            role: role,
            message: message,
            metadata: drift.Value(encodedMetadata),
          ),
        );
    _scrollToBottom();
    return insertedId;
  }

  String? _encodeTimelineMetadata(Map<String, dynamic> metadataPayload) {
    if (metadataPayload.isEmpty) {
      return null;
    }
    return jsonEncode(_jsonSafeMetadataValue(metadataPayload));
  }

  Object? _jsonSafeMetadataValue(Object? value) {
    if (value == null || value is String || value is bool) {
      return value;
    }
    if (value is num) {
      return value.isFinite ? value : value.toString();
    }
    if (value is Map<Object?, Object?>) {
      return value.map(
        (key, mapValue) =>
            MapEntry(key.toString(), _jsonSafeMetadataValue(mapValue)),
      );
    }
    if (value is Iterable<Object?>) {
      return value.map(_jsonSafeMetadataValue).toList(growable: false);
    }
    return value.toString();
  }

  Future<void> _persistTimelineEntrySafely({
    required String role,
    required String message,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      await _insertTimelineEntry(
        role: role,
        message: message,
        metadata: metadata,
      );
    } on Exception catch (exception) {
      _showSnackBar('Unable to persist runtime update: $exception');
    }
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
    final sanitizedMessage = _TimelineMarkdownBody.sanitizeText(
      timelineEvent.message,
    );
    if (timelineEvent.type == AiTimelineEventType.error) {
      _runtimeStarted = false;
      if (sanitizedMessage.isEmpty) {
        return;
      }
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

    // For ACP sessions, the AcpClient handles errors directly — downgrade
    // redundant runtime error events (e.g., "exited with code 127") to status
    // to avoid duplicate red-box error entries.
    final isAcpSession = _acpClient != null;
    final role = switch (timelineEvent.type) {
      AiTimelineEventType.message => 'assistant',
      AiTimelineEventType.tool => 'tool',
      AiTimelineEventType.thinking => 'thinking',
      AiTimelineEventType.status => 'status',
      AiTimelineEventType.error => isAcpSession ? 'status' : 'error',
    };

    unawaited(
      _persistTimelineEntrySafely(
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
      _persistTimelineEntrySafely(
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
    final metadata = AiSessionMetadata.decode(entry.metadata);
    if (role == 'status') {
      return _StatusTimelineEntry(entry: entry);
    }
    if (role == 'tool' || role == 'thinking' || role == 'error') {
      return _SystemTimelineEntry(entry: entry, role: role, metadata: metadata);
    }
    return _MessageTimelineEntry(entry: entry, role: role, metadata: metadata);
  }
}

class _MessageTimelineEntry extends StatelessWidget {
  const _MessageTimelineEntry({
    required this.entry,
    required this.role,
    required this.metadata,
  });

  final AiTimelineEntry entry;
  final String role;
  final Map<String, dynamic> metadata;

  @override
  Widget build(BuildContext context) {
    final isUser = role == 'user';
    final theme = Theme.of(context);
    final containerColor = isUser
        ? theme.colorScheme.primaryContainer
        : theme.colorScheme.surfaceContainerHighest;
    final contentColor = isUser
        ? theme.colorScheme.onPrimaryContainer
        : theme.colorScheme.onSurface;
    final sectionLabel = isUser ? 'Prompt' : 'Assistant';
    final icon = isUser ? Icons.person_outline : Icons.smart_toy_outlined;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 760),
        margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: containerColor,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _EntryRoleBadge(
                icon: icon,
                label: sectionLabel,
                color: contentColor,
              ),
              const SizedBox(height: 8),
              _TimelineMarkdownBody(
                data: entry.message,
                textColor: contentColor,
              ),
              if (_AiTimelineEntryFormatting.hasStructuredPayload(metadata))
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: _TimelineMetadataSection(
                    title: 'Structured payload',
                    content: _AiTimelineEntryFormatting.prettyPayload(metadata),
                    textColor: contentColor,
                  ),
                ),
            ],
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
  Widget build(BuildContext context) {
    final sanitizedMessage = _TimelineMarkdownBody.sanitizeText(entry.message);
    if (sanitizedMessage.isEmpty) {
      return const SizedBox.shrink();
    }
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          sanitizedMessage,
          style: Theme.of(context).textTheme.labelMedium,
        ),
      ),
    );
  }
}

class _SystemTimelineEntry extends StatelessWidget {
  const _SystemTimelineEntry({
    required this.entry,
    required this.role,
    required this.metadata,
  });

  final AiTimelineEntry entry;
  final String role;
  final Map<String, dynamic> metadata;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final sanitizedMessage = _TimelineMarkdownBody.sanitizeText(entry.message);
    final toolName = _AiTimelineEntryFormatting.extractToolName(metadata);
    final toolKind = _AiTimelineEntryFormatting.extractToolKind(metadata);
    final toolStatus = _AiTimelineEntryFormatting.extractToolStatus(metadata);
    final inputSummary = _AiTimelineEntryFormatting.extractInput(metadata);
    final outputSummary = _AiTimelineEntryFormatting.extractOutput(metadata);
    final isSubagent = _AiTimelineEntryFormatting.isSubagentCall(metadata);
    final hasPayload = _AiTimelineEntryFormatting.hasStructuredPayload(
      metadata,
    );
    final hasVisibleMessage = sanitizedMessage.isNotEmpty;
    final hasSupplementalContent =
        toolName != null ||
        toolKind != null ||
        inputSummary != null ||
        outputSummary != null ||
        hasPayload;
    if (!hasVisibleMessage && !hasSupplementalContent) {
      return const SizedBox.shrink();
    }
    final messageText = hasVisibleMessage
        ? entry.message
        : role == 'error'
        ? 'Runtime error (no details provided).'
        : '';
    final heading = switch (role) {
      'tool' => isSubagent ? 'Subagent call' : 'Tool call',
      'thinking' => 'Model thinking',
      'error' => 'Runtime error',
      _ => 'System event',
    };
    final (icon, tint, background) = switch (role) {
      'tool' => (
        isSubagent ? Icons.smart_toy_outlined : Icons.build_circle_outlined,
        colorScheme.onSecondaryContainer,
        colorScheme.secondaryContainer,
      ),
      'thinking' => (
        Icons.psychology_alt_outlined,
        colorScheme.onTertiaryContainer,
        colorScheme.tertiaryContainer,
      ),
      'error' => (
        Icons.error_outline,
        colorScheme.onErrorContainer,
        colorScheme.errorContainer,
      ),
      _ => (
        Icons.info_outline,
        colorScheme.onPrimaryContainer,
        colorScheme.primaryContainer,
      ),
    };
    final toolSummary = role == 'tool'
        ? [
            if (toolKind != null && toolKind.isNotEmpty) 'Tool: $toolKind',
            if (toolStatus != null && toolStatus.isNotEmpty) toolStatus,
          ].join(' · ')
        : null;
    final shouldCollapseByDefault =
        role == 'tool' &&
        toolStatus != null &&
        !_AiTimelineEntryFormatting.isToolActive(metadata);
    final initiallyExpanded = !shouldCollapseByDefault;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      constraints: const BoxConstraints(maxWidth: 760),
      child: Card(
        color: background,
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            key: PageStorageKey<String>('ai-system-entry-${entry.id}'),
            initiallyExpanded: initiallyExpanded,
            iconColor: tint,
            collapsedIconColor: tint,
            tilePadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 4,
            ),
            childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            title: _EntryRoleBadge(icon: icon, label: heading, color: tint),
            subtitle: toolSummary != null && toolSummary.isNotEmpty
                ? Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      toolSummary,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: tint),
                    ),
                  )
                : null,
            children: [
              if (toolName != null && toolName.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: tint.withAlpha(26),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    toolName,
                    style: Theme.of(
                      context,
                    ).textTheme.labelMedium?.copyWith(color: tint),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              if (messageText.isNotEmpty)
                _TimelineMarkdownBody(data: messageText, textColor: tint),
              if (inputSummary != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: _TimelineMetadataSection(
                    title: 'Input',
                    content: inputSummary,
                    textColor: tint,
                  ),
                ),
              if (outputSummary != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: _TimelineMetadataSection(
                    title: 'Output',
                    content: outputSummary,
                    textColor: tint,
                  ),
                ),
              if (hasPayload)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: _TimelineMetadataSection(
                    title: 'Payload',
                    content: _AiTimelineEntryFormatting.prettyPayload(metadata),
                    textColor: tint,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CliRuntimeTelemetry {
  const _CliRuntimeTelemetry({
    this.model,
    this.mode,
    this.contextRemainingTokens,
    this.contextUsedTokens,
  });

  final String? model;
  final String? mode;
  final int? contextRemainingTokens;
  final int? contextUsedTokens;
}

class _EntryRoleBadge extends StatelessWidget {
  const _EntryRoleBadge({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 16, color: color),
      const SizedBox(width: 6),
      Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    ],
  );
}

class _TimelineMarkdownBody extends StatelessWidget {
  const _TimelineMarkdownBody({required this.data, required this.textColor});

  static final RegExp _ansiEscapePattern = RegExp(
    '\u001B\\[[0-9;?]*[ -/]*[@-~]',
  );
  static final RegExp _oscEscapePattern = RegExp(
    '\u001B\\][^\\u0007]*(\\u0007|\u001B\\\\)',
  );
  static final RegExp _unsafeControlPattern = RegExp(
    r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]',
  );

  final String data;
  final Color textColor;

  static String sanitizeText(String value) => value
      .replaceAll(_ansiEscapePattern, '')
      .replaceAll(_oscEscapePattern, '')
      .replaceAll(_unsafeControlPattern, '')
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n');

  @override
  Widget build(BuildContext context) {
    final sanitizedData = sanitizeText(data);
    final fallbackTextStyle = Theme.of(
      context,
    ).textTheme.bodyMedium?.copyWith(color: textColor);
    if (sanitizedData.isEmpty) {
      return const SizedBox.shrink();
    }

    final styleSheet = MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
      p: Theme.of(context).textTheme.bodyMedium?.copyWith(color: textColor),
      code: Theme.of(context).textTheme.bodyMedium?.copyWith(
        color: textColor,
        fontFamily: 'monospace',
      ),
      blockquote: Theme.of(
        context,
      ).textTheme.bodyMedium?.copyWith(color: textColor.withAlpha(220)),
    );
    final hasTerminalFormattingArtifacts =
        _ansiEscapePattern.hasMatch(data) ||
        _oscEscapePattern.hasMatch(data) ||
        _unsafeControlPattern.hasMatch(data) ||
        data.contains('\r');
    if (hasTerminalFormattingArtifacts) {
      return SelectableText(sanitizedData, style: fallbackTextStyle);
    }
    return MarkdownBody(
      data: sanitizedData,
      styleSheet: styleSheet,
      sizedImageBuilder: (config) =>
          Text(config.alt ?? '[image]', style: fallbackTextStyle),
      onTapLink: (text, href, title) {},
    );
  }
}

class _TimelineMetadataSection extends StatelessWidget {
  const _TimelineMetadataSection({
    required this.title,
    required this.content,
    required this.textColor,
  });

  final String title;
  final String content;
  final Color textColor;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: textColor.withAlpha(20),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: textColor.withAlpha(40)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(color: textColor),
        ),
        const SizedBox(height: 4),
        _TimelineMarkdownBody(data: content, textColor: textColor),
      ],
    ),
  );
}

abstract final class _AiTimelineEntryFormatting {
  static bool hasStructuredPayload(Map<String, dynamic> metadata) =>
      _payloadMap(metadata).isNotEmpty;

  static bool isSubagentCall(Map<String, dynamic> metadata) {
    final payload = _payloadMap(metadata);
    final subagent = _readString(payload, const <String>['subagent', 'agent']);
    if (subagent != null) {
      return true;
    }
    final name = extractToolName(metadata);
    return name != null &&
        (name.toLowerCase().contains('agent') ||
            name.toLowerCase().contains('subagent'));
  }

  static String? extractToolName(Map<String, dynamic> metadata) {
    final payload = _payloadMap(metadata);
    return _readString(payload, const <String>[
          'toolName',
          'tool',
          'name',
          'command',
        ]) ??
        _readString(metadata, const <String>[
          'toolName',
          'tool',
          'name',
          'command',
        ]);
  }

  static String? extractToolKind(Map<String, dynamic> metadata) {
    final payload = _payloadMap(metadata);
    return _readString(payload, const <String>['toolKind', 'kind', 'tool']) ??
        _readString(metadata, const <String>['toolKind', 'kind', 'tool']);
  }

  static String? extractToolStatus(Map<String, dynamic> metadata) {
    final payload = _payloadMap(metadata);
    return _readString(payload, const <String>[
          'toolStatus',
          'status',
          'state',
        ]) ??
        _readString(metadata, const <String>['toolStatus', 'status', 'state']);
  }

  static bool isToolActive(Map<String, dynamic> metadata) {
    final status = extractToolStatus(metadata)?.toLowerCase();
    if (status == null) {
      return false;
    }
    return status.contains('pending') ||
        status.contains('running') ||
        status.contains('in_progress') ||
        status.contains('started') ||
        status.contains('executing');
  }

  static String? extractInput(Map<String, dynamic> metadata) {
    final payload = _payloadMap(metadata);
    return _readString(payload, const <String>[
          'input',
          'arguments',
          'args',
          'prompt',
        ]) ??
        _readString(metadata, const <String>[
          'input',
          'arguments',
          'args',
          'prompt',
        ]);
  }

  static String? extractOutput(Map<String, dynamic> metadata) {
    final payload = _payloadMap(metadata);
    return _readString(payload, const <String>[
          'output',
          'result',
          'response',
        ]) ??
        _readString(metadata, const <String>['output', 'result', 'response']);
  }

  static String prettyPayload(Map<String, dynamic> metadata) {
    final payload = _payloadMap(metadata);
    if (payload.isEmpty) {
      return '';
    }
    const encoder = JsonEncoder.withIndent('  ');
    final encodedPayload = encoder.convert(_jsonSafeValue(payload));
    return '```json\n$encodedPayload\n```';
  }

  static Map<String, dynamic> _payloadMap(Map<String, dynamic> metadata) {
    final payload = metadata['payload'];
    if (payload is Map<String, dynamic>) {
      return payload;
    }
    if (payload is Map<Object?, Object?>) {
      return payload.map((key, value) => MapEntry(key.toString(), value));
    }
    return const <String, dynamic>{};
  }

  static String? _readString(Map<String, dynamic> source, List<String> keys) {
    for (final key in keys) {
      final resolved = _stringifyValue(source[key]);
      if (resolved != null && resolved.trim().isNotEmpty) {
        return resolved.trim();
      }
    }
    return null;
  }

  static String? _stringifyValue(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is String) {
      return value;
    }
    if (value is num || value is bool) {
      return value.toString();
    }
    if (value is Map<String, dynamic>) {
      return jsonEncode(_jsonSafeValue(value));
    }
    if (value is Map<Object?, Object?>) {
      return jsonEncode(_jsonSafeValue(value));
    }
    if (value is List<Object?>) {
      return jsonEncode(_jsonSafeValue(value));
    }
    return value.toString();
  }

  static Object? _jsonSafeValue(Object? value) {
    if (value == null || value is String || value is num || value is bool) {
      return value;
    }
    if (value is Map<Object?, Object?>) {
      return value.map(
        (key, mapValue) => MapEntry(key.toString(), _jsonSafeValue(mapValue)),
      );
    }
    if (value is Iterable<Object?>) {
      return value.map(_jsonSafeValue).toList(growable: false);
    }
    return value.toString();
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
