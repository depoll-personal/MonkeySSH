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
  const AiStartSessionScreen({
    super.key,
    this.embedInScaffold = true,
    this.acpAdapterInstalledChecker,
    this.acpAdapterInstaller,
  });

  /// Whether this screen should render with its own [Scaffold].
  final bool embedInScaffold;

  /// Optional override for checking whether the ACP adapter is installed.
  final Future<bool> Function(
    WidgetRef ref,
    int connectionId,
    AiCliProvider provider,
  )?
  acpAdapterInstalledChecker;

  /// Optional override for installing the ACP adapter on the remote host.
  final Future<bool> Function(
    WidgetRef ref,
    int connectionId,
    AiCliProvider provider,
  )?
  acpAdapterInstaller;

  @override
  ConsumerState<AiStartSessionScreen> createState() =>
      _AiStartSessionScreenState();
}

class _AiStartSessionScreenState extends ConsumerState<AiStartSessionScreen> {
  static const _customAcpClientId = '__custom__';
  static const _acpAdapterVersion = 'v0.3.3';
  static const _remoteShellPathPrefix =
      r'/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$HOME/bin:'
      r'$HOME/homebrew/bin:$HOME/.homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin';
  static const _acpAdapterInstallCommand =
      'export PATH="$_remoteShellPathPrefix:\$PATH"; '
      r'INSTALL_DIR="${XDG_BIN_HOME:-$HOME/.local/bin}"; '
      r'mkdir -p "$INSTALL_DIR"; '
      'if ! command -v curl >/dev/null 2>&1; then '
      'echo "curl is required to install acp-adapter." >&2; '
      'exit 1; '
      'fi; '
      'if ! command -v sha256sum >/dev/null 2>&1 && '
      '! command -v shasum >/dev/null 2>&1; then '
      'echo "sha256 verification requires sha256sum or shasum." >&2; '
      'exit 1; '
      'fi; '
      r'OS="$(uname -s)"; ARCH="$(uname -m)"; '
      r'case "$OS" in Linux) OS=linux ;; Darwin) OS=darwin ;; '
      r'*) echo "Unsupported operating system: $OS" >&2; exit 1 ;; esac; '
      r'case "$ARCH" in x86_64|amd64) ARCH=x86_64 ;; arm64|aarch64) ARCH=aarch64 ;; '
      r'*) echo "Unsupported architecture: $ARCH" >&2; exit 1 ;; esac; '
      'FILENAME="acp-adapter-'
      '$_acpAdapterVersion'
      r'-${ARCH}-${OS}.tar.gz"; '
      'URL="https://github.com/beyond5959/acp-adapter/releases/download/'
      '$_acpAdapterVersion'
      r'/${FILENAME}"; '
      r'EXPECTED_SHA="$(case "${ARCH}-${OS}" in '
      'x86_64-darwin) printf %s 1c03d3d1e396ba0e978c3b8265744537f9600bffa559362277f456f1468a23be ;; '
      'aarch64-darwin) printf %s 78637244a753c9a1efcfd386062920516ebddbe1bf2809aab019aabe754dbb36 ;; '
      'x86_64-linux) printf %s 0ae60e30db2daad2a803c6b38c8d2514a6744b62c1cb1ac4561ba80b33ae6fb7 ;; '
      'aarch64-linux) printf %s 20d235dd70d3e98bcab1a06f51bef3c25c95293cd91d3fcce1ac643810aa02da ;; '
      '*) exit 1 ;; esac)"; '
      r'TMP_DIR="$(mktemp -d 2>/dev/null || mktemp -d -t acp-adapter)"; '
      "trap 'rm -rf \"\$TMP_DIR\"' EXIT; "
      r'ARCHIVE="$TMP_DIR/$FILENAME"; '
      r'curl -fsSL "$URL" -o "$ARCHIVE"; '
      r'ACTUAL_SHA="$(if command -v sha256sum >/dev/null 2>&1; then '
      r'''sha256sum "$ARCHIVE" | awk '{print $1}'; '''
      r'''else shasum -a 256 "$ARCHIVE" | awk '{print $1}'; fi)"; '''
      r'if [ "$ACTUAL_SHA" != "$EXPECTED_SHA" ]; then '
      'echo "Checksum verification failed for acp-adapter." >&2; '
      'exit 1; '
      'fi; '
      r'if ! tar -tzf "$ARCHIVE" >/dev/null 2>&1; then '
      'echo "Downloaded acp-adapter archive is invalid." >&2; '
      'exit 1; '
      'fi; '
      r'tar -xzf "$ARCHIVE" -C "$TMP_DIR"; '
      r'BINARY_PATH="$(find "$TMP_DIR" -type f -name acp-adapter | head -n 1)"; '
      r'if [ -z "$BINARY_PATH" ] || [ ! -f "$BINARY_PATH" ]; then '
      'echo "acp-adapter binary not found in extracted archive." >&2; '
      r'find "$TMP_DIR" -maxdepth 2 -mindepth 1 -print >&2; '
      'exit 1; '
      'fi; '
      r'chmod +x "$BINARY_PATH"; '
      r'mv "$BINARY_PATH" "$INSTALL_DIR/acp-adapter"; '
      r'"$INSTALL_DIR/acp-adapter" --version >/dev/null 2>&1 || { '
      'echo "Installed acp-adapter failed to start." >&2; '
      'exit 1; '
      '}; '
      r'printf %s "$INSTALL_DIR/acp-adapter"';
  static const _acpAdapterProbeCommand =
      'export PATH="$_remoteShellPathPrefix:\$PATH"; '
      r'for candidate in "$(command -v acp-adapter 2>/dev/null)" '
      r'"${XDG_BIN_HOME:-$HOME/.local/bin}/acp-adapter" '
      r'"$HOME/bin/acp-adapter" '
      r'"$HOME/homebrew/bin/acp-adapter" '
      r'"$HOME/.homebrew/bin/acp-adapter" '
      '"/usr/local/bin/acp-adapter" '
      '"/opt/homebrew/bin/acp-adapter"; do '
      r'if [ -n "$candidate" ] && [ -x "$candidate" ]; then '
      r'printf %s "$candidate"; '
      'exit 0; '
      'fi; '
      'done; '
      'exit 1';

  late final TextEditingController _workingDirectoryController;
  late final TextEditingController _acpClientCommandController;
  AiCliProvider _selectedProvider = AiCliProvider.claude;
  String _selectedAcpClientId = knownAcpClientPresets.first.id;
  int? _selectedHostId;
  bool _isStarting = false;
  bool _providerSelectionTouched = false;
  bool _acpClientSelectionTouched = false;

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
                        key: ValueKey<String>(
                          'ai-provider-field-${_selectedProvider.name}',
                        ),
                        initialValue: _selectedProvider,
                        decoration: const InputDecoration(
                          labelText: 'AI provider',
                          border: OutlineInputBorder(),
                        ),
                        items: AiCliProvider.values
                            .map(
                              (provider) => DropdownMenuItem<AiCliProvider>(
                                value: provider,
                                child: Text(
                                  provider.executable,
                                  key: Key(
                                    'ai-provider-option-${provider.name}',
                                  ),
                                ),
                              ),
                            )
                            .toList(growable: false),
                        onChanged: (provider) {
                          if (provider == null) {
                            return;
                          }
                          setState(() {
                            _providerSelectionTouched = true;
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
                        if (!_isValidAcpClientSelection(
                          _selectedAcpClientId,
                        )) ...[
                          Builder(
                            builder: (context) {
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (!mounted) {
                                  return;
                                }
                                final fallbackClientId =
                                    knownAcpClientPresets.first.id;
                                setState(() {
                                  _selectedAcpClientId = fallbackClientId;
                                  _acpClientCommandController.text =
                                      knownAcpClientPresets.first.command;
                                });
                              });
                              return const SizedBox.shrink();
                            },
                          ),
                        ],
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          key: ValueKey<String>(
                            'ai-acp-client-preset-field-$_resolvedAcpClientSelection',
                          ),
                          initialValue: _resolvedAcpClientSelection,
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
                              _acpClientSelectionTouched = true;
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
      key: ValueKey<int>(resolvedHostId),
      initialValue: resolvedHostId,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Host',
        border: OutlineInputBorder(),
      ),
      selectedItemBuilder: (context) => hosts
          .map(
            (host) => Align(
              alignment: Alignment.centerLeft,
              child: Text(
                host.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          )
          .toList(growable: false),
      items: hosts
          .map(
            (host) => DropdownMenuItem<int>(
              value: host.id,
              child: Text(
                '${host.label} (${host.username}@${host.hostname})',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
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
    key: const Key('ai-recent-sessions-card'),
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
        : session.acpClientLabel ??
              (provider == AiCliProvider.acp
                  ? session.executableOverride
                  : null) ??
              provider.executable;
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
      key: Key('ai-recent-session-tile-${session.sessionId}'),
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
    if (hostsAsync.isLoading) {
      _showSnackBar('Hosts are still loading. Please wait a moment.');
      return;
    }
    if (hostsAsync.hasError) {
      _showSnackBar('Unable to load hosts: ${hostsAsync.error}');
      return;
    }
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
    var providerForSession = _selectedProvider;
    String? acpExecutableOverride;
    String? acpClientLabel;
    String? acpClientId;
    if (providerForSession == AiCliProvider.acp) {
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

      final adapterSelection = await _resolveClaudeOrCodexAdapterSelection(
        connectionId: connectionResult.connectionId!,
        provider: providerForSession,
      );
      if (adapterSelection == null) {
        if (!connectionResult.reusedConnection) {
          await ref
              .read(activeSessionsProvider.notifier)
              .disconnect(connectionResult.connectionId!);
        }
        return;
      }
      providerForSession = adapterSelection.provider;
      final transportForSession =
          adapterSelection.transport ??
          providerForSession.capabilities.defaultTransport;
      acpExecutableOverride = adapterSelection.executableOverride;
      acpClientLabel = adapterSelection.acpClientLabel;
      acpClientId = adapterSelection.acpClientId;
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

      final repository = ref.read(aiRepositoryProvider);
      final workspaceId = await _resolveWorkspaceId(
        repository: repository,
        host: selectedHost,
        workingDirectory: workingDirectory,
      );
      final sessionTitle = acpClientLabel ?? providerForSession.executable;
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
              'provider': providerForSession.name,
              'transport': transportForSession.name,
              'originalProvider': providerForSession.name,
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
          'provider': providerForSession.name,
          'workingDir': workingDirectory,
          'transport': transportForSession.name,
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
    final existingWorkspace = await repository.getWorkspaceByPath(
      workingDirectory,
    );
    if (existingWorkspace != null) {
      return existingWorkspace.id;
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

  Future<_AiStartSessionLaunchSelection?>
  _resolveClaudeOrCodexAdapterSelection({
    required int connectionId,
    required AiCliProvider provider,
  }) async {
    if (!_supportsRecommendedAcpAdapter(provider)) {
      return _AiStartSessionLaunchSelection(provider: provider);
    }

    final isInstalled = await _isAcpAdapterInstalled(
      connectionId: connectionId,
      provider: provider,
    );
    if (isInstalled) {
      _showSnackBar('Using acp-adapter for ${provider.executable}.');
      return _recommendedAcpSelection(provider);
    }

    if (!mounted) {
      return null;
    }

    final action = await _showAcpAdapterInstallDialog(provider: provider);
    if (!mounted) {
      return null;
    }
    switch (action) {
      case _AcpAdapterPromptAction.install:
        final installed = await _installAcpAdapter(
          connectionId: connectionId,
          provider: provider,
        );
        if (!installed) {
          return null;
        }
        _showSnackBar(
          'Installed acp-adapter. Starting ${provider.executable} via ACP.',
        );
        return _recommendedAcpSelection(provider);
      case _AcpAdapterPromptAction.continueWithoutAdapter:
        return _AiStartSessionLaunchSelection(provider: provider);
      case _AcpAdapterPromptAction.cancel:
      case null:
        return null;
    }
  }

  bool _supportsRecommendedAcpAdapter(AiCliProvider provider) =>
      provider == AiCliProvider.claude || provider == AiCliProvider.codex;

  _AiStartSessionLaunchSelection _recommendedAcpSelection(
    AiCliProvider provider,
  ) {
    final presetId = switch (provider) {
      AiCliProvider.claude => 'claude-acp',
      AiCliProvider.codex => 'codex-acp',
      _ => throw ArgumentError.value(provider, 'provider'),
    };
    final preset = knownAcpClientPresets.firstWhere(
      (candidate) => candidate.id == presetId,
    );
    return _AiStartSessionLaunchSelection(
      provider: provider,
      transport: AiCliTransport.acp,
      executableOverride: preset.command,
      acpClientLabel: preset.label,
      acpClientId: preset.id,
    );
  }

  Future<bool> _isAcpAdapterInstalled({
    required int connectionId,
    required AiCliProvider provider,
  }) async {
    final overrideChecker = widget.acpAdapterInstalledChecker;
    if (overrideChecker != null) {
      return overrideChecker(ref, connectionId, provider);
    }
    try {
      final result = await _runRemoteCommand(
        connectionId: connectionId,
        command: _acpAdapterProbeCommand,
      );
      return result.exitCode == 0 && result.stdout.trim().isNotEmpty;
    } on Exception catch (error) {
      _showSnackBar('Unable to check acp-adapter on the remote host: $error');
      return false;
    }
  }

  Future<bool> _installAcpAdapter({
    required int connectionId,
    required AiCliProvider provider,
  }) async {
    final overrideInstaller = widget.acpAdapterInstaller;
    if (overrideInstaller != null) {
      return overrideInstaller(ref, connectionId, provider);
    }
    try {
      final result = await _runRemoteCommand(
        connectionId: connectionId,
        command: _acpAdapterInstallCommand,
      );
      if (result.exitCode != 0) {
        _showSnackBar(_summarizeRemoteCommandFailure(result));
        return false;
      }
      return _isAcpAdapterInstalled(
        connectionId: connectionId,
        provider: provider,
      );
    } on Exception catch (error) {
      _showSnackBar('ACP adapter install failed: $error');
      return false;
    }
  }

  String _summarizeRemoteCommandFailure(_RemoteCommandResult result) {
    final combined = [
      result.stderr.trim(),
      result.stdout.trim(),
    ].where((value) => value.isNotEmpty).join('\n').trim();
    if (combined.isEmpty) {
      return 'Unable to install acp-adapter on the remote host.';
    }
    const maxLength = 400;
    final clipped = combined.length > maxLength
        ? '${combined.substring(0, maxLength)}…'
        : combined;
    return 'ACP adapter install failed (exit ${result.exitCode ?? 'unknown'}): $clipped';
  }

  Future<_RemoteCommandResult> _runRemoteCommand({
    required int connectionId,
    required String command,
  }) async {
    final session = ref
        .read(activeSessionsProvider.notifier)
        .getSession(connectionId);
    if (session == null) {
      throw StateError('SSH session $connectionId is no longer available.');
    }
    final process = await session.execute(
      'sh -lc ${_shellSingleQuote(command)}',
    );
    final stdoutFuture = process.stdout
        .cast<List<int>>()
        .transform(utf8.decoder)
        .join();
    final stderrFuture = process.stderr
        .cast<List<int>>()
        .transform(utf8.decoder)
        .join();
    await process.done;
    return _RemoteCommandResult(
      stdout: await stdoutFuture,
      stderr: await stderrFuture,
      exitCode: process.exitCode,
    );
  }

  Future<_AcpAdapterPromptAction?> _showAcpAdapterInstallDialog({
    required AiCliProvider provider,
  }) => showDialog<_AcpAdapterPromptAction>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      key: const Key('ai-acp-adapter-install-dialog'),
      title: Text('Install ACP adapter for ${provider.executable}?'),
      content: Text(
        '${provider.executable} works best in MonkeySSH through `acp-adapter`, '
        'which enables the native ACP chat flow for slash commands, tool calls, '
        'and session control.\n\n'
        'MonkeySSH can install the adapter on the remote host now and then start '
        'the session using the ACP bridge automatically.',
      ),
      actions: [
        TextButton(
          onPressed: () =>
              Navigator.of(dialogContext).pop(_AcpAdapterPromptAction.cancel),
          child: const Text('Cancel'),
        ),
        TextButton(
          key: const Key('ai-continue-without-acp-adapter-button'),
          onPressed: () => Navigator.of(
            dialogContext,
          ).pop(_AcpAdapterPromptAction.continueWithoutAdapter),
          child: const Text('Continue Directly'),
        ),
        FilledButton(
          key: const Key('ai-install-acp-adapter-button'),
          onPressed: () =>
              Navigator.of(dialogContext).pop(_AcpAdapterPromptAction.install),
          child: const Text('Install Adapter'),
        ),
      ],
    ),
  );

  String _shellSingleQuote(String value) =>
      "'${value.replaceAll("'", r"'\''")}'";

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
    if (provider != null && mounted && !_providerSelectionTouched) {
      setState(() {
        _selectedProvider = provider;
      });
    }
    final acpClientId = AiSessionMetadata.readString(metadata, 'acpClientId');
    if (acpClientId != null && mounted && !_acpClientSelectionTouched) {
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

  String get _resolvedAcpClientSelection =>
      _isValidAcpClientSelection(_selectedAcpClientId)
      ? _selectedAcpClientId
      : knownAcpClientPresets.first.id;

  bool _isValidAcpClientSelection(String clientId) =>
      clientId == _customAcpClientId ||
      knownAcpClientPresets.any((preset) => preset.id == clientId);
}

enum _AcpAdapterPromptAction { install, continueWithoutAdapter, cancel }

class _AiStartSessionLaunchSelection {
  const _AiStartSessionLaunchSelection({
    required this.provider,
    this.transport,
    this.executableOverride,
    this.acpClientLabel,
    this.acpClientId,
  });

  final AiCliProvider provider;
  final AiCliTransport? transport;
  final String? executableOverride;
  final String? acpClientLabel;
  final String? acpClientId;
}

class _RemoteCommandResult {
  const _RemoteCommandResult({
    required this.stdout,
    required this.stderr,
    required this.exitCode,
  });

  final String stdout;
  final String stderr;
  final int? exitCode;
}

final _aiHostsProvider = FutureProvider.autoDispose<List<Host>>((ref) {
  final hostRepository = ref.watch(hostRepositoryProvider);
  return hostRepository.getAll();
});

final _recentAiSessionsProvider =
    StreamProvider.autoDispose<List<_AiSessionResumeSummary>>(
      (ref) => ref
          .watch(aiRepositoryProvider)
          .watchRecentSessions()
          .asyncMap(
            (sessions) => Future.wait(
              sessions.map((session) async {
                final repository = ref.read(aiRepositoryProvider);
                final workspace = await repository.getWorkspaceById(
                  session.workspaceId,
                );
                final timelineEntry = await repository.getLatestTimelineEntry(
                  session.id,
                );
                final metadata = AiSessionMetadata.decode(
                  timelineEntry?.metadata,
                );
                return _AiSessionResumeSummary(
                  sessionId: session.id,
                  title: session.title,
                  provider: AiSessionMetadata.readOriginalProvider(metadata),
                  executableOverride: AiSessionMetadata.readString(
                    metadata,
                    'executableOverride',
                  ),
                  acpClientLabel: AiSessionMetadata.readString(
                    metadata,
                    'acpClientLabel',
                  ),
                  connectionId: AiSessionMetadata.readInt(
                    metadata,
                    'connectionId',
                  ),
                  hostId: AiSessionMetadata.readInt(metadata, 'hostId'),
                  workingDirectory:
                      AiSessionMetadata.readString(
                        metadata,
                        'workingDirectory',
                      ) ??
                      workspace?.path ??
                      '~',
                );
              }),
            ),
          ),
    );

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
