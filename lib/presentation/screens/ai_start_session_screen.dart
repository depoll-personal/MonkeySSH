import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/database/database.dart';
import '../../data/repositories/ai_repository.dart';
import '../../data/repositories/host_repository.dart';
import '../../domain/models/ai_cli_provider.dart';
import '../../domain/services/ai_session_metadata.dart';
import '../../domain/services/ssh_service.dart';

/// Start flow for creating a new AI chat session.
class AiStartSessionScreen extends ConsumerStatefulWidget {
  /// Creates an [AiStartSessionScreen].
  const AiStartSessionScreen({super.key, this.embedInScaffold = true});

  /// Whether this screen should render with its own [Scaffold].
  final bool embedInScaffold;

  @override
  ConsumerState<AiStartSessionScreen> createState() =>
      _AiStartSessionScreenState();
}

class _AiStartSessionScreenState extends ConsumerState<AiStartSessionScreen> {
  static const _customAcpClientId = '__custom__';

  late final TextEditingController _workingDirectoryController;
  late final TextEditingController _acpClientCommandController;
  AiCliProvider _selectedProvider = AiCliProvider.claude;
  String _selectedAcpClientId = knownAcpClientPresets.first.id;
  int? _selectedHostId;
  bool _isStarting = false;

  @override
  void initState() {
    super.initState();
    _workingDirectoryController = TextEditingController(text: '~');
    _acpClientCommandController = TextEditingController();
    unawaited(_restoreLastUsedProviderSelection());
  }

  @override
  void dispose() {
    _workingDirectoryController.dispose();
    _acpClientCommandController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hostsAsync = ref.watch(_aiHostsProvider);
    final recentSessionsAsync = ref.watch(_recentAiSessionsProvider);
    final activeConnections = ref.watch(activeSessionsProvider);
    final content = SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'AI Chat',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Start a remote AI session by choosing a host, working directory, and provider.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      hostsAsync.when(
                        loading: _buildLoadingHostField,
                        error: (error, _) => _buildErrorHostField(error),
                        data: _buildHostField,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        key: const Key('ai-working-directory-field'),
                        controller: _workingDirectoryController,
                        decoration: const InputDecoration(
                          labelText: 'Working directory',
                          hintText: '~/project',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<AiCliProvider>(
                        key: const Key('ai-provider-field'),
                        initialValue: _selectedProvider,
                        decoration: const InputDecoration(
                          labelText: 'AI provider',
                          border: OutlineInputBorder(),
                        ),
                        items: AiCliProvider.values
                            .map(
                              (provider) => DropdownMenuItem<AiCliProvider>(
                                value: provider,
                                child: Text(provider.executable),
                              ),
                            )
                            .toList(growable: false),
                        onChanged: (provider) {
                          if (provider == null) {
                            return;
                          }
                          setState(() {
                            _selectedProvider = provider;
                            if (provider == AiCliProvider.acp &&
                                _selectedAcpClientId != _customAcpClientId) {
                              final preset = _selectedAcpClientPreset;
                              if (preset != null) {
                                _acpClientCommandController.text =
                                    preset.command;
                              }
                            }
                          });
                        },
                      ),
                      if (_selectedProvider == AiCliProvider.acp) ...[
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          key: const Key('ai-acp-client-preset-field'),
                          initialValue: _selectedAcpClientId,
                          decoration: const InputDecoration(
                            labelText: 'ACP client',
                            border: OutlineInputBorder(),
                          ),
                          items: <DropdownMenuItem<String>>[
                            ...knownAcpClientPresets.map(
                              (preset) => DropdownMenuItem<String>(
                                value: preset.id,
                                child: Text(preset.label),
                              ),
                            ),
                            const DropdownMenuItem<String>(
                              value: _customAcpClientId,
                              child: Text('Custom command'),
                            ),
                          ],
                          onChanged: (value) {
                            if (value == null) {
                              return;
                            }
                            setState(() {
                              _selectedAcpClientId = value;
                              final preset = _selectedAcpClientPreset;
                              if (value == _customAcpClientId) {
                                _acpClientCommandController.clear();
                              } else if (preset != null) {
                                _acpClientCommandController.text =
                                    preset.command;
                              }
                            });
                          },
                        ),
                        if (_selectedAcpClientId == _customAcpClientId) ...[
                          const SizedBox(height: 12),
                          TextField(
                            key: const Key('ai-acp-client-command-field'),
                            controller: _acpClientCommandController,
                            decoration: const InputDecoration(
                              labelText: 'Custom ACP client command',
                              hintText: 'my-acp-client --stdio',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ] else ...[
                          const SizedBox(height: 8),
                          Text(
                            'Command: ${_selectedAcpClientPreset?.command ?? _acpClientCommandController.text}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ],
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _isStarting || hostsAsync.isLoading
                              ? null
                              : () => unawaited(_startSession(hostsAsync)),
                          icon: _isStarting
                              ? const SizedBox.square(
                                  dimension: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.play_arrow_rounded),
                          label: Text(
                            _isStarting ? 'Starting...' : 'Start Session',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _buildRecentSessionsCard(
                recentSessionsAsync,
                activeConnections: activeConnections,
              ),
            ],
          ),
        ),
      ),
    );

    if (!widget.embedInScaffold) {
      return content;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('AI Chat')),
      body: content,
    );
  }

  Widget _buildLoadingHostField() => const InputDecorator(
    decoration: InputDecoration(
      labelText: 'Host',
      border: OutlineInputBorder(),
    ),
    child: SizedBox(
      height: 20,
      child: Align(
        alignment: Alignment.centerLeft,
        child: SizedBox.square(
          dimension: 14,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    ),
  );

  Widget _buildErrorHostField(Object error) => InputDecorator(
    decoration: const InputDecoration(
      labelText: 'Host',
      border: OutlineInputBorder(),
    ),
    child: Text('Unable to load hosts: $error'),
  );

  Widget _buildHostField(List<Host> hosts) {
    if (hosts.isEmpty) {
      return const InputDecorator(
        decoration: InputDecoration(
          labelText: 'Host',
          border: OutlineInputBorder(),
        ),
        child: Text('Add a host first to start AI chat.'),
      );
    }

    final selectedHostStillExists =
        _selectedHostId != null &&
        hosts.any((host) => host.id == _selectedHostId);
    final resolvedHostId = selectedHostStillExists
        ? _selectedHostId!
        : hosts.first.id;
    if (_selectedHostId != resolvedHostId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        setState(() {
          _selectedHostId = resolvedHostId;
        });
      });
    }

    return DropdownButtonFormField<int>(
      key: const Key('ai-host-field'),
      initialValue: resolvedHostId,
      decoration: const InputDecoration(
        labelText: 'Host',
        border: OutlineInputBorder(),
      ),
      items: hosts
          .map(
            (host) => DropdownMenuItem<int>(
              value: host.id,
              child: Text('${host.label} (${host.username}@${host.hostname})'),
            ),
          )
          .toList(growable: false),
      onChanged: (hostId) {
        setState(() {
          _selectedHostId = hostId;
        });
      },
    );
  }

  Widget _buildRecentSessionsCard(
    AsyncValue<List<_AiSessionResumeSummary>> recentSessionsAsync, {
    required Map<int, SshConnectionState> activeConnections,
  }) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Recent sessions',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          recentSessionsAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: SizedBox(
                height: 20,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: SizedBox.square(
                    dimension: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
            ),
            error: (error, _) => Text('Unable to load sessions: $error'),
            data: (sessions) {
              if (sessions.isEmpty) {
                return Text(
                  'No previous sessions yet. Start one to build history.',
                  style: Theme.of(context).textTheme.bodyMedium,
                );
              }
              return Column(
                children: sessions
                    .map(
                      (session) => _buildRecentSessionTile(
                        session,
                        canReattach:
                            session.connectionId != null &&
                            activeConnections.containsKey(session.connectionId),
                      ),
                    )
                    .toList(growable: false),
              );
            },
          ),
        ],
      ),
    ),
  );

  Widget _buildRecentSessionTile(
    _AiSessionResumeSummary session, {
    required bool canReattach,
  }) {
    final provider = session.provider;
    final providerLabel = provider == null
        ? 'Provider unknown'
        : provider == AiCliProvider.acp
        ? session.acpClientLabel ??
              session.executableOverride ??
              provider.executable
        : provider.executable;
    final trailing = canReattach
        ? const Tooltip(
            message: 'Runtime available for resume',
            child: Icon(Icons.link_rounded, size: 18),
          )
        : const Tooltip(
            message: 'Transcript only until runtime reconnects',
            child: Icon(Icons.link_off_rounded, size: 18),
          );
    final subtitleParts = <String>[
      providerLabel,
      session.workingDirectory,
      if (canReattach) 'runtime ready' else 'runtime detached',
    ];
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(session.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        subtitleParts.join(' · '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: trailing,
      onTap: () => unawaited(_resumeSession(session)),
    );
  }

  Future<void> _resumeSession(_AiSessionResumeSummary session) async {
    final parameters = <String, String>{'resume': '1'};
    final provider = session.provider;
    if (provider != null) {
      parameters['provider'] = provider.name;
    }
    if (session.connectionId != null) {
      parameters['connectionId'] = session.connectionId.toString();
    }
    if (session.hostId != null) {
      parameters['hostId'] = session.hostId.toString();
    }
    if (session.workingDirectory.isNotEmpty) {
      parameters['workingDir'] = session.workingDirectory;
    }
    if (session.executableOverride != null &&
        session.executableOverride!.isNotEmpty) {
      parameters['executable'] = session.executableOverride!;
    }

    final uri = Uri(
      path: '/ai/session/${session.sessionId}',
      queryParameters: parameters,
    );
    await context.push(uri.toString());
  }

  Future<void> _startSession(AsyncValue<List<Host>> hostsAsync) async {
    final hosts = hostsAsync.asData?.value ?? const <Host>[];
    if (hosts.isEmpty) {
      _showSnackBar('Add a host before starting an AI session.');
      return;
    }
    if (_selectedHostId == null) {
      _showSnackBar('Select a host to continue.');
      return;
    }

    final workingDirectory = _workingDirectoryController.text.trim();
    if (workingDirectory.isEmpty) {
      _showSnackBar('Working directory is required.');
      return;
    }
    String? acpExecutableOverride;
    String? acpClientLabel;
    String? acpClientId;
    if (_selectedProvider == AiCliProvider.acp) {
      if (_selectedAcpClientId == _customAcpClientId) {
        final customCommand = _acpClientCommandController.text.trim();
        if (customCommand.isEmpty) {
          _showSnackBar('ACP client command is required.');
          return;
        }
        acpExecutableOverride = customCommand;
        acpClientLabel = 'Custom command';
        acpClientId = _customAcpClientId;
      } else {
        final preset = _selectedAcpClientPreset;
        if (preset == null) {
          _showSnackBar('Select an ACP client.');
          return;
        }
        acpExecutableOverride = preset.command;
        acpClientLabel = preset.label;
        acpClientId = preset.id;
      }
    }

    Host? selectedHost;
    for (final host in hosts) {
      if (host.id == _selectedHostId) {
        selectedHost = host;
        break;
      }
    }
    if (selectedHost == null) {
      _showSnackBar('Selected host is no longer available.');
      return;
    }
    final acpExecutableMetadata = acpExecutableOverride == null
        ? null
        : <String, dynamic>{'executableOverride': acpExecutableOverride};
    final acpClientMetadata = <String, dynamic>{};
    if (acpClientLabel != null) {
      acpClientMetadata['acpClientLabel'] = acpClientLabel;
    }
    if (acpClientId != null) {
      acpClientMetadata['acpClientId'] = acpClientId;
    }
    final acpExecutableQueryParam = acpExecutableOverride == null
        ? null
        : <String, String>{'executable': acpExecutableOverride};

    setState(() {
      _isStarting = true;
    });

    try {
      final connectionResult = await ref
          .read(activeSessionsProvider.notifier)
          .connect(selectedHost.id);
      if (!connectionResult.success || connectionResult.connectionId == null) {
        _showSnackBar(connectionResult.error ?? 'Unable to connect to host.');
        return;
      }

      final repository = ref.read(aiRepositoryProvider);
      final workspaceId = await _resolveWorkspaceId(
        repository: repository,
        host: selectedHost,
        workingDirectory: workingDirectory,
      );
      final sessionTitle = acpClientLabel ?? _selectedProvider.executable;
      final sessionId = await repository.insertSession(
        AiSessionsCompanion.insert(
          workspaceId: workspaceId,
          title: '$sessionTitle · ${selectedHost.label}',
          status: const drift.Value('active'),
        ),
      );
      await repository.insertTimelineEntry(
        AiTimelineEntriesCompanion.insert(
          sessionId: sessionId,
          role: 'status',
          message:
              'Connected to ${selectedHost.username}@${selectedHost.hostname} in $workingDirectory.',
          metadata: drift.Value(
            jsonEncode(<String, dynamic>{
              'connectionId': connectionResult.connectionId,
              'provider': _selectedProvider.name,
              'hostId': selectedHost.id,
              'workingDirectory': workingDirectory,
              ...?acpExecutableMetadata,
              ...acpClientMetadata,
              'runtimeState': 'attached',
            }),
          ),
        ),
      );

      if (!mounted) {
        return;
      }

      final sessionUri = Uri(
        path: '/ai/session/$sessionId',
        queryParameters: <String, String>{
          'connectionId': connectionResult.connectionId!.toString(),
          'provider': _selectedProvider.name,
          'workingDir': workingDirectory,
          ...?acpExecutableQueryParam,
        },
      );
      await context.push(sessionUri.toString());
    } finally {
      if (mounted) {
        setState(() {
          _isStarting = false;
        });
      }
    }
  }

  Future<int> _resolveWorkspaceId({
    required AiRepository repository,
    required Host host,
    required String workingDirectory,
  }) async {
    final existingWorkspaces = await repository.getAllWorkspaces();
    for (final workspace in existingWorkspaces) {
      if (workspace.path == workingDirectory) {
        return workspace.id;
      }
    }

    return repository.insertWorkspace(
      AiWorkspacesCompanion.insert(
        name: '${host.label} Workspace',
        path: workingDirectory,
      ),
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

  /// Restores the last-used provider and ACP preset from the most recent
  /// session metadata.
  Future<void> _restoreLastUsedProviderSelection() async {
    final repository = ref.read(aiRepositoryProvider);
    final sessions = await repository.getRecentSessions();
    if (sessions.isEmpty) {
      return;
    }
    final latestSession = sessions.first;
    final latestEntry = await repository.getLatestTimelineEntry(
      latestSession.id,
    );
    if (latestEntry == null) {
      return;
    }
    final metadata = AiSessionMetadata.decode(latestEntry.metadata);
    final provider = AiSessionMetadata.readProvider(metadata);
    if (provider != null && mounted) {
      setState(() {
        _selectedProvider = provider;
      });
    }
    final acpClientId = AiSessionMetadata.readString(metadata, 'acpClientId');
    if (acpClientId != null && mounted) {
      setState(() {
        _selectedAcpClientId = acpClientId;
      });
    }
    final acpExecutable = AiSessionMetadata.readString(
      metadata,
      'executableOverride',
    );
    if (acpClientId == _customAcpClientId && acpExecutable != null && mounted) {
      _acpClientCommandController.text = acpExecutable;
    }
  }

  AcpClientPreset? get _selectedAcpClientPreset {
    for (final preset in knownAcpClientPresets) {
      if (preset.id == _selectedAcpClientId) {
        return preset;
      }
    }
    return null;
  }
}

final _aiHostsProvider = FutureProvider.autoDispose<List<Host>>((ref) {
  final hostRepository = ref.watch(hostRepositoryProvider);
  return hostRepository.getAll();
});

final _recentAiSessionsProvider =
    FutureProvider.autoDispose<List<_AiSessionResumeSummary>>((ref) async {
      final repository = ref.watch(aiRepositoryProvider);
      final sessions = await repository.getRecentSessions();
      return Future.wait(
        sessions.map((session) async {
          final workspace = await repository.getWorkspaceById(
            session.workspaceId,
          );
          final timelineEntry = await repository.getLatestTimelineEntry(
            session.id,
          );
          final metadata = AiSessionMetadata.decode(timelineEntry?.metadata);
          return _AiSessionResumeSummary(
            sessionId: session.id,
            title: session.title,
            provider: AiSessionMetadata.readProvider(metadata),
            executableOverride: AiSessionMetadata.readString(
              metadata,
              'executableOverride',
            ),
            acpClientLabel: AiSessionMetadata.readString(
              metadata,
              'acpClientLabel',
            ),
            connectionId: AiSessionMetadata.readInt(metadata, 'connectionId'),
            hostId: AiSessionMetadata.readInt(metadata, 'hostId'),
            workingDirectory:
                AiSessionMetadata.readString(metadata, 'workingDirectory') ??
                workspace?.path ??
                '~',
          );
        }),
      );
    });

class _AiSessionResumeSummary {
  const _AiSessionResumeSummary({
    required this.sessionId,
    required this.title,
    required this.workingDirectory,
    this.provider,
    this.executableOverride,
    this.acpClientLabel,
    this.connectionId,
    this.hostId,
  });

  final int sessionId;
  final String title;
  final AiCliProvider? provider;
  final int? connectionId;
  final int? hostId;
  final String workingDirectory;
  final String? executableOverride;
  final String? acpClientLabel;
}
