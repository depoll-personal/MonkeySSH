import 'dart:async';
import 'dart:collection';

import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../data/database/database.dart';
import '../../data/repositories/host_repository.dart';
import '../../data/repositories/key_repository.dart';
import '../../data/repositories/snippet_repository.dart';
import '../../domain/models/terminal_theme.dart';
import '../../domain/models/terminal_themes.dart';
import '../../domain/services/auth_service.dart';
import '../../domain/services/secure_transfer_service.dart';
import '../../domain/services/settings_service.dart';
import '../../domain/services/ssh_service.dart';
import '../../domain/services/terminal_theme_service.dart';
import '../../domain/services/transfer_intent_service.dart';
import '../providers/entity_list_providers.dart';
import '../widgets/connection_attempt_dialog.dart';
import '../widgets/connection_preview_snippet.dart';
import 'transfer_screen.dart';

/// The main home screen - Termius-style sidebar layout.
class HomeScreen extends ConsumerStatefulWidget {
  /// Creates a new [HomeScreen].
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with WidgetsBindingObserver {
  int _selectedIndex = 0;
  StreamSubscription<String>? _incomingTransferSubscription;
  final Queue<String> _incomingTransferQueue = Queue<String>();
  String? _activeIncomingTransferPayload;
  bool _isHandlingIncomingTransfer = false;

  // Breakpoint for switching between mobile and desktop layout
  static const double _mobileBreakpoint = 600;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final transferIntentService = ref.read(transferIntentServiceProvider);
    _incomingTransferSubscription = transferIntentService.incomingPayloads
        .listen((payload) {
          if (payload.isNotEmpty && mounted) {
            _enqueueIncomingTransferPayload(payload);
          }
        });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_checkIncomingTransferPayload());
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_incomingTransferSubscription?.cancel());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_checkIncomingTransferPayload());
    }
  }

  Future<void> _checkIncomingTransferPayload() async {
    final payload = await ref
        .read(transferIntentServiceProvider)
        .consumeIncomingTransferPayload();
    if (!mounted || payload == null || payload.isEmpty) {
      return;
    }
    _enqueueIncomingTransferPayload(payload);
  }

  void _enqueueIncomingTransferPayload(String encodedPayload) {
    final normalizedPayload = encodedPayload.trim();
    if (normalizedPayload.isEmpty ||
        normalizedPayload == _activeIncomingTransferPayload ||
        _incomingTransferQueue.contains(normalizedPayload)) {
      return;
    }
    _incomingTransferQueue.add(normalizedPayload);
    unawaited(_processIncomingTransferQueue());
  }

  Future<void> _processIncomingTransferQueue() async {
    if (_isHandlingIncomingTransfer) {
      return;
    }
    while (mounted && _incomingTransferQueue.isNotEmpty) {
      _isHandlingIncomingTransfer = true;
      final encodedPayload = _incomingTransferQueue.removeFirst();
      _activeIncomingTransferPayload = encodedPayload;
      try {
        await _handleIncomingTransferPayload(encodedPayload);
      } finally {
        _activeIncomingTransferPayload = null;
        _isHandlingIncomingTransfer = false;
      }
    }
  }

  Future<void> _handleIncomingTransferPayload(String encodedPayload) async {
    try {
      final transferPassphrase = await showTransferPassphraseDialog(
        context: context,
        title: 'Incoming transfer passphrase',
      );
      if (!mounted || transferPassphrase == null) {
        return;
      }

      final transferService = ref.read(secureTransferServiceProvider);
      final payload = await transferService.decryptPayload(
        encodedPayload: encodedPayload,
        transferPassphrase: transferPassphrase,
      );

      switch (payload.type) {
        case TransferPayloadType.host:
          final host = await transferService.importHostPayload(payload);
          ref.invalidate(allHostsProvider);
          if (!mounted) {
            return;
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Imported host: ${host.label}')),
          );
          break;
        case TransferPayloadType.key:
          final key = await transferService.importKeyPayload(payload);
          ref.invalidate(allKeysProvider);
          if (!mounted) {
            return;
          }
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Imported key: ${key.name}')));
          break;
        case TransferPayloadType.fullMigration:
          final preview = transferService.previewMigrationPayload(payload);
          if (!mounted) {
            return;
          }
          final mode = await showMigrationImportModeDialog(
            context: context,
            preview: preview,
            title: 'Incoming migration package',
            message: 'Choose how to apply the incoming data.',
          );
          if (mode == null || !mounted) {
            return;
          }
          await transferService.importFullMigrationPayload(
            payload: payload,
            mode: mode,
          );
          ref
            ..invalidate(themeModeNotifierProvider)
            ..invalidate(fontSizeNotifierProvider)
            ..invalidate(fontFamilyNotifierProvider)
            ..invalidate(cursorStyleNotifierProvider)
            ..invalidate(bellSoundNotifierProvider)
            ..invalidate(terminalThemeSettingsProvider)
            ..invalidate(allHostsProvider)
            ..invalidate(allKeysProvider);
          if (!mounted) {
            return;
          }
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Imported full migration package')),
          );
          break;
      }
    } on FormatException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Import failed: ${error.message}')),
      );
    } on Exception catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Import failed: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isWide = screenWidth >= _mobileBreakpoint;

    return isWide ? _buildDesktopLayout() : _buildMobileLayout();
  }

  Widget _buildMobileLayout() => Scaffold(
    backgroundColor: Colors.transparent,
    extendBody: true,
    body: SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
        child: Column(
          children: [
            _ShellHeader(onSettingsTap: () => context.push('/settings')),
            const SizedBox(height: 12),
            Expanded(child: _ShellPanel(child: _buildContent())),
          ],
        ),
      ),
    ),
    bottomNavigationBar: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: FluttyGlassSurface(
          borderRadius: BorderRadius.circular(28),
          blurSigma: 18,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: NavigationBar(
            selectedIndex: _selectedIndex,
            onDestinationSelected: (index) =>
                setState(() => _selectedIndex = index),
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.dns_outlined),
                selectedIcon: Icon(Icons.dns_rounded),
                label: 'Hosts',
              ),
              NavigationDestination(
                icon: Icon(Icons.link_outlined),
                selectedIcon: Icon(Icons.link),
                label: 'Connections',
              ),
              NavigationDestination(
                icon: Icon(Icons.key_outlined),
                selectedIcon: Icon(Icons.key_rounded),
                label: 'Keys',
              ),
              NavigationDestination(
                icon: Icon(Icons.code_outlined),
                selectedIcon: Icon(Icons.code_rounded),
                label: 'Snippets',
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _buildDesktopLayout() => Scaffold(
    backgroundColor: Colors.transparent,
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            SizedBox(
              width: 248,
              child: FluttyGlassSurface(
                borderRadius: BorderRadius.circular(34),
                blurSigma: 20,
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                child: Column(
                  children: [
                    const _ShellHeader(showSettingsAction: false),
                    const SizedBox(height: 14),
                    _NavItem(
                      icon: Icons.dns_rounded,
                      label: 'Hosts',
                      selected: _selectedIndex == 0,
                      onTap: () => setState(() => _selectedIndex = 0),
                    ),
                    _NavItem(
                      icon: Icons.link,
                      label: 'Connections',
                      selected: _selectedIndex == 1,
                      onTap: () => setState(() => _selectedIndex = 1),
                    ),
                    _NavItem(
                      icon: Icons.key_rounded,
                      label: 'Keys',
                      selected: _selectedIndex == 2,
                      onTap: () => setState(() => _selectedIndex = 2),
                    ),
                    _NavItem(
                      icon: Icons.code_rounded,
                      label: 'Snippets',
                      selected: _selectedIndex == 3,
                      onTap: () => setState(() => _selectedIndex = 3),
                    ),
                    const Spacer(),
                    _NavItem(
                      icon: Icons.settings_outlined,
                      label: 'Settings',
                      selected: false,
                      onTap: () => context.push('/settings'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(child: _ShellPanel(child: _buildContent())),
          ],
        ),
      ),
    ),
  );

  Widget _buildContent() {
    switch (_selectedIndex) {
      case 0:
        return const _HostsPanel();
      case 1:
        return const _ConnectionsPanel();
      case 2:
        return const _KeysPanel();
      case 3:
        return const _SnippetsPanel();
      default:
        return const _HostsPanel();
    }
  }
}

class _ShellHeader extends StatelessWidget {
  const _ShellHeader({this.onSettingsTap, this.showSettingsAction = true});

  final VoidCallback? onSettingsTap;
  final bool showSettingsAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return FluttyGlassSurface(
      borderRadius: BorderRadius.circular(28),
      blurSigma: 18,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Row(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: FluttyTheme.accentGradient,
              borderRadius: BorderRadius.circular(18),
              boxShadow: FluttyTheme.glowShadow(colorScheme.primary),
            ),
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.asset(
                  'assets/icons/monkeyssh_icon.png',
                  width: 42,
                  height: 42,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'MonkeySSH',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Liquid terminal workspace',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (showSettingsAction)
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              tooltip: 'Settings',
              onPressed: onSettingsTap,
              style: IconButton.styleFrom(
                foregroundColor: colorScheme.onSurface,
                backgroundColor: colorScheme.surfaceContainerHigh.withAlpha(
                  110,
                ),
                padding: const EdgeInsets.all(12),
              ),
            ),
        ],
      ),
    );
  }
}

class _ShellPanel extends StatelessWidget {
  const _ShellPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => FluttyGlassSurface(
    borderRadius: BorderRadius.circular(34),
    blurSigma: 20,
    padding: EdgeInsets.zero,
    child: child,
  );
}

class _PanelShell extends StatelessWidget {
  const _PanelShell({required this.title, required this.child, this.trailing});

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final headerChildren = <Widget>[
      Container(
        width: 11,
        height: 11,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [colorScheme.primary, colorScheme.secondary.withAlpha(200)],
          ),
          boxShadow: [
            BoxShadow(color: colorScheme.primary.withAlpha(80), blurRadius: 12),
          ],
        ),
      ),
      const SizedBox(width: 12),
      Text(
        title,
        style: theme.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
      const Spacer(),
    ];
    if (trailing != null) {
      headerChildren.add(trailing!);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 20, 18, 16),
          child: Row(children: headerChildren),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Divider(color: colorScheme.outlineVariant.withAlpha(180)),
        ),
        Expanded(child: child),
      ],
    );
  }
}

class _EmptyPanelState extends StatelessWidget {
  const _EmptyPanelState({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: FluttyGlassSurface(
          borderRadius: BorderRadius.circular(28),
          blurSigma: 16,
          padding: const EdgeInsets.fromLTRB(28, 28, 28, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      colorScheme.primary.withAlpha(86),
                      colorScheme.secondary.withAlpha(56),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Icon(icon, size: 30, color: colorScheme.onSurface),
              ),
              const SizedBox(height: 18),
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              if (action != null) ...[const SizedBox(height: 18), action!],
            ],
          ),
        ),
      ),
    );
  }
}

class _InteractiveGlassTile extends StatelessWidget {
  const _InteractiveGlassTile({required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    child: FluttyGlassSurface(
      borderRadius: BorderRadius.circular(24),
      blurSigma: 14,
      padding: EdgeInsets.zero,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            child: child,
          ),
        ),
      ),
    ),
  );
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: selected
                    ? [
                        colorScheme.primary.withAlpha(74),
                        colorScheme.secondary.withAlpha(44),
                      ]
                    : [
                        Colors.white.withAlpha(
                          theme.brightness == Brightness.dark ? 4 : 92,
                        ),
                        Colors.white.withAlpha(
                          theme.brightness == Brightness.dark ? 1 : 48,
                        ),
                      ],
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: selected
                    ? colorScheme.primary.withAlpha(100)
                    : colorScheme.outlineVariant.withAlpha(140),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: selected
                        ? colorScheme.onSurface.withAlpha(24)
                        : colorScheme.surfaceContainerHigh.withAlpha(120),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    icon,
                    size: 18,
                    color: selected
                        ? colorScheme.onSurface
                        : colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: selected
                          ? colorScheme.onSurface
                          : colorScheme.onSurfaceVariant,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HostsPanel extends ConsumerWidget {
  const _HostsPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hostsAsync = ref.watch(allHostsProvider);

    return _PanelShell(
      title: 'Hosts',
      trailing: _ActionButton(
        icon: Icons.add,
        label: 'New Host',
        onTap: () => context.push('/hosts/add'),
        primary: true,
      ),
      child: hostsAsync.when(
        loading: () =>
            const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (hosts) => hosts.isEmpty
            ? _buildEmptyState(context)
            : _buildHostsList(context, ref, hosts),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) => _EmptyPanelState(
    icon: Icons.dns_outlined,
    title: 'No hosts yet',
    message: 'Add a host to get started.',
    action: FilledButton.icon(
      onPressed: () => context.push('/hosts/add'),
      icon: const Icon(Icons.add, size: 18),
      label: const Text('Add Host'),
    ),
  );

  Widget _buildHostsList(
    BuildContext context,
    WidgetRef ref,
    List<Host> hosts,
  ) => ListView.builder(
    padding: const EdgeInsets.fromLTRB(0, 10, 0, 22),
    itemCount: hosts.length,
    itemBuilder: (context, index) {
      final host = hosts[index];
      return _HostRow(host: host);
    },
  );
}

class _HostRow extends ConsumerWidget {
  const _HostRow({required this.host});

  final Host host;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final sessionsNotifier = ref.read(activeSessionsProvider.notifier);
    final connectionStates = ref.watch(activeSessionsProvider);
    final connectionIds = sessionsNotifier.getConnectionsForHost(host.id);
    final hostConnectionStates = connectionIds
        .map((connectionId) => connectionStates[connectionId])
        .whereType<SshConnectionState>()
        .toList(growable: false);
    final isConnected = hostConnectionStates.any(
      (state) => state == SshConnectionState.connected,
    );
    final isConnecting = hostConnectionStates.any(
      (state) =>
          state == SshConnectionState.connecting ||
          state == SshConnectionState.authenticating,
    );
    final connectionAttempt = sessionsNotifier.getConnectionAttempt(host.id);
    final isConnectionStarting =
        isConnecting || (connectionAttempt?.isInProgress ?? false);
    final connectionCount = connectionIds.length;
    final terminalThemeSettings = ref.watch(terminalThemeSettingsProvider);
    final terminalThemes =
        ref.watch(allTerminalThemesProvider).asData?.value ??
        TerminalThemes.all;
    final previewEntries = connectionIds
        .map((connectionId) {
          final connection = sessionsNotifier.getActiveConnection(connectionId);
          final state =
              connectionStates[connectionId] ?? SshConnectionState.connected;
          return buildConnectionPreviewStackEntry(
            connectionId: connectionId,
            state: state,
            preview: connection?.preview,
            windowTitle: connection?.windowTitle,
            iconName: connection?.iconName,
            workingDirectory: connection?.workingDirectory,
            shellStatus: connection?.shellStatus,
            lastExitCode: connection?.lastExitCode,
            brightness: theme.brightness,
            themeSettings: terminalThemeSettings,
            availableThemes: terminalThemes,
            hostLightThemeId: host.terminalThemeLightId,
            hostDarkThemeId: host.terminalThemeDarkId,
            connectionLightThemeId: connection?.terminalThemeLightId,
            connectionDarkThemeId: connection?.terminalThemeDarkId,
          );
        })
        .toList(growable: false);

    return _InteractiveGlassTile(
      onTap: () => unawaited(_openHostConnection(context, ref)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      (isConnected
                              ? colorScheme.primary
                              : isConnectionStarting
                              ? colorScheme.tertiary
                              : colorScheme.secondary)
                          .withAlpha(92),
                      colorScheme.surfaceContainerHigh.withAlpha(110),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isConnected
                          ? colorScheme.primary
                          : isConnectionStarting
                          ? colorScheme.tertiary
                          : colorScheme.onSurface.withAlpha(70),
                      boxShadow: isConnected && isDark
                          ? [
                              BoxShadow(
                                color: colorScheme.primary.withAlpha(120),
                                blurRadius: 12,
                                spreadRadius: 1,
                              ),
                            ]
                          : null,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            host.label,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (connectionCount > 0) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: colorScheme.primary.withAlpha(22),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              '$connectionCount live',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: colorScheme.primary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                        if (host.isFavorite) ...[
                          const SizedBox(width: 6),
                          Icon(
                            Icons.star_rounded,
                            size: 16,
                            color: Colors.amber.shade500,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${host.username}@${host.hostname}',
                      style: FluttyTheme.monoStyle.copyWith(
                        fontSize: 11,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (connectionAttempt?.isInProgress ?? false) ...[
                      const SizedBox(height: 6),
                      Text(
                        connectionAttempt!.latestMessage,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHigh.withAlpha(110),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      ':${host.port}',
                      style: FluttyTheme.monoStyle.copyWith(
                        fontSize: 10,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _SmallIconButton(
                        icon: Icons.add,
                        onTap: () =>
                            unawaited(_openNewConnection(context, ref)),
                      ),
                      _SmallIconButton(
                        icon: Icons.edit_outlined,
                        onTap: () => context.push('/hosts/edit/${host.id}'),
                      ),
                      _SmallIconButton(
                        icon: Icons.more_horiz_rounded,
                        onTap: () => _showMenu(context, ref),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          if (previewEntries.isNotEmpty) ...[
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.only(left: 56),
              child: ConnectionPreviewStack(entries: previewEntries),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _openHostConnection(BuildContext context, WidgetRef ref) async {
    final sessionsNotifier = ref.read(activeSessionsProvider.notifier);
    final connectionIds = sessionsNotifier.getConnectionsForHost(host.id);

    if (connectionIds.isEmpty) {
      await _openNewConnection(context, ref);
      return;
    }

    if (connectionIds.length == 1) {
      if (context.mounted) {
        unawaited(
          context.push(
            '/terminal/${host.id}?connectionId=${connectionIds.first}',
          ),
        );
      }
      return;
    }

    final selection = await showModalBottomSheet<String>(
      context: context,
      builder: (context) {
        final connectionStates = ref.read(activeSessionsProvider);
        final terminalThemeSettings = ref.read(terminalThemeSettingsProvider);
        final terminalThemes =
            ref.read(allTerminalThemesProvider).asData?.value ??
            TerminalThemes.all;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(host.label),
                subtitle: Text('${connectionIds.length} active connections'),
              ),
              for (final connectionId in connectionIds.reversed)
                () {
                  final connection = sessionsNotifier.getActiveConnection(
                    connectionId,
                  );
                  return _ConnectionSelectionTile(
                    connectionId: connectionId,
                    state:
                        connectionStates[connectionId] ??
                        SshConnectionState.disconnected,
                    endpoint: '${host.username}@${host.hostname}:${host.port}',
                    preview: connection?.preview,
                    windowTitle: connection?.windowTitle,
                    iconName: connection?.iconName,
                    workingDirectory: connection?.workingDirectory,
                    shellStatus: connection?.shellStatus,
                    lastExitCode: connection?.lastExitCode,
                    terminalTheme: resolveConnectionPreviewTheme(
                      brightness: Theme.of(context).brightness,
                      themeSettings: terminalThemeSettings,
                      availableThemes: terminalThemes,
                      lightThemeId:
                          connection?.terminalThemeLightId ??
                          host.terminalThemeLightId,
                      darkThemeId:
                          connection?.terminalThemeDarkId ??
                          host.terminalThemeDarkId,
                    ),
                    createdAt: sessionsNotifier
                        .getSession(connectionId)
                        ?.createdAt,
                    onTap: () =>
                        Navigator.pop(context, 'connection:$connectionId'),
                  );
                }(),
              ListTile(
                leading: const Icon(Icons.add),
                title: const Text('New connection'),
                onTap: () => Navigator.pop(context, 'new'),
              ),
            ],
          ),
        );
      },
    );

    if (!context.mounted || selection == null) {
      return;
    }

    if (selection == 'new') {
      await _openNewConnection(context, ref);
      return;
    }

    final selectedId = int.tryParse(selection.replaceFirst('connection:', ''));
    if (selectedId != null) {
      unawaited(context.push('/terminal/${host.id}?connectionId=$selectedId'));
    }
  }

  Future<void> _openNewConnection(BuildContext context, WidgetRef ref) async {
    final result = await connectToHostWithProgressDialog(context, ref, host);

    if (!context.mounted) {
      return;
    }

    if (!result.success || result.connectionId == null) {
      return;
    }

    unawaited(
      context.push('/terminal/${host.id}?connectionId=${result.connectionId}'),
    );
  }

  void _showMenu(BuildContext context, WidgetRef ref) {
    final parentContext = context;
    final colorScheme = Theme.of(context).colorScheme;

    showModalBottomSheet<void>(
      context: parentContext,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('Duplicate'),
              onTap: () {
                Navigator.pop(sheetContext);
                unawaited(_duplicateHost(parentContext, ref));
              },
            ),
            ListTile(
              leading: const Icon(Icons.save_alt),
              title: const Text('Export Encrypted File'),
              onTap: () {
                Navigator.pop(sheetContext);
                unawaited(_exportEncryptedFile(parentContext, ref));
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: colorScheme.error),
              title: Text('Delete', style: TextStyle(color: colorScheme.error)),
              onTap: () {
                Navigator.pop(sheetContext);
                _confirmDelete(parentContext, ref);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _exportEncryptedFile(BuildContext context, WidgetRef ref) async {
    if ((host.password?.isNotEmpty ?? false) || host.keyId != null) {
      final isAuthorized = await authorizeSensitiveTransferExport(
        context: context,
        authService: ref.read(authServiceProvider),
        reason: 'Authenticate to export host credentials',
      );
      if (!context.mounted) {
        return;
      }
      if (!isAuthorized) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Authentication required for host export'),
          ),
        );
        return;
      }
    }

    final transferPassphrase = await showTransferPassphraseDialog(
      context: context,
      title: 'Host transfer passphrase',
    );
    if (!context.mounted || transferPassphrase == null) {
      return;
    }

    final payload = await ref
        .read(secureTransferServiceProvider)
        .createHostPayload(
          host: host,
          transferPassphrase: transferPassphrase,
          includeReferencedKey: host.keyId != null,
        );

    if (!context.mounted) {
      return;
    }

    final defaultFileName = sanitizeTransferFileBaseName(
      'host-${host.label.toLowerCase().replaceAll(' ', '-')}',
    );

    await saveTransferPayloadToFile(
      context: context,
      payload: payload,
      defaultFileName: defaultFileName,
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Host'),
        content: Text('Delete "${host.label}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if ((confirmed ?? false) && context.mounted) {
      await ref.read(hostRepositoryProvider).delete(host.id);
    }
  }

  Future<void> _duplicateHost(BuildContext context, WidgetRef ref) async {
    await ref.read(hostRepositoryProvider).duplicate(host);
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Host duplicated')));
    }
  }
}

class _ConnectionSelectionTile extends StatelessWidget {
  const _ConnectionSelectionTile({
    required this.connectionId,
    required this.state,
    required this.endpoint,
    required this.onTap,
    this.preview,
    this.windowTitle,
    this.iconName,
    this.workingDirectory,
    this.shellStatus,
    this.lastExitCode,
    this.terminalTheme,
    this.createdAt,
  });

  final int connectionId;
  final SshConnectionState state;
  final String endpoint;
  final String? preview;
  final String? windowTitle;
  final String? iconName;
  final Uri? workingDirectory;
  final TerminalShellStatus? shellStatus;
  final int? lastExitCode;
  final TerminalThemeData? terminalTheme;
  final DateTime? createdAt;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final subtitle = createdAt == null
        ? endpoint
        : '$endpoint\nOpened ${_formatTime(createdAt!)}';
    return ListTile(
      leading: const Icon(Icons.terminal),
      title: Text('Connection #$connectionId'),
      subtitle: _ConnectionPreviewText(
        endpoint: subtitle,
        preview: preview,
        windowTitle: windowTitle,
        iconName: iconName,
        workingDirectory: workingDirectory,
        shellStatus: shellStatus,
        lastExitCode: lastExitCode,
        terminalTheme: terminalTheme,
      ),
      isThreeLine: preview?.trim().isNotEmpty ?? false,
      trailing: Text(
        _stateLabel(state),
        style: Theme.of(context).textTheme.labelMedium,
      ),
      onTap: onTap,
    );
  }

  String _stateLabel(SshConnectionState state) => switch (state) {
    SshConnectionState.connected => 'Connected',
    SshConnectionState.connecting => 'Connecting',
    SshConnectionState.authenticating => 'Auth',
    SshConnectionState.reconnecting => 'Reconnecting',
    SshConnectionState.error => 'Error',
    SshConnectionState.disconnected => 'Disconnected',
  };

  String _formatTime(DateTime time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}

class _ConnectionsPanel extends ConsumerWidget {
  const _ConnectionsPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final hostsAsync = ref.watch(allHostsProvider);
    final connectionStates = ref.watch(activeSessionsProvider);
    final sessionsNotifier = ref.read(activeSessionsProvider.notifier);
    final terminalThemeSettings = ref.watch(terminalThemeSettingsProvider);
    final terminalThemes =
        ref.watch(allTerminalThemesProvider).asData?.value ??
        TerminalThemes.all;
    final connections = sessionsNotifier.getActiveConnections();
    final hosts = hostsAsync.asData?.value ?? <Host>[];
    final hostLookup = {for (final host in hosts) host.id: host};

    return _PanelShell(
      title: 'Connections',
      child: connections.isEmpty
          ? _buildEmptyState(context)
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(0, 10, 0, 22),
              itemCount: connections.length,
              itemBuilder: (context, index) {
                final connection = connections[index];
                final host = hostLookup[connection.hostId];
                final state =
                    connectionStates[connection.connectionId] ??
                    connection.state;
                final endpoint =
                    '${connection.config.username}@'
                    '${connection.config.hostname}:${connection.config.port}';
                final preview = connection.preview;
                final previewTheme = resolveConnectionPreviewTheme(
                  brightness: theme.brightness,
                  themeSettings: terminalThemeSettings,
                  availableThemes: terminalThemes,
                  lightThemeId:
                      connection.terminalThemeLightId ??
                      host?.terminalThemeLightId,
                  darkThemeId:
                      connection.terminalThemeDarkId ??
                      host?.terminalThemeDarkId,
                );

                return _InteractiveGlassTile(
                  onTap: () => unawaited(
                    context.push(
                      '/terminal/${connection.hostId}'
                      '?connectionId=${connection.connectionId}',
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              (state == SshConnectionState.connected
                                      ? Theme.of(context).colorScheme.primary
                                      : Theme.of(context).colorScheme.secondary)
                                  .withAlpha(90),
                              Theme.of(
                                context,
                              ).colorScheme.surfaceContainerHigh.withAlpha(100),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          Icons.terminal,
                          color: state == SshConnectionState.connected
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              host?.label ?? 'Host ${connection.hostId}',
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 6),
                            _ConnectionPreviewText(
                              endpoint:
                                  '$endpoint  •  Connection #${connection.connectionId}',
                              preview: preview,
                              windowTitle: connection.windowTitle,
                              iconName: connection.iconName,
                              workingDirectory: connection.workingDirectory,
                              shellStatus: connection.shellStatus,
                              lastExitCode: connection.lastExitCode,
                              terminalTheme: previewTheme,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      IconButton(
                        icon: const Icon(Icons.close),
                        tooltip: 'Disconnect',
                        onPressed: () async {
                          await ref
                              .read(activeSessionsProvider.notifier)
                              .disconnect(connection.connectionId);
                        },
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  Widget _buildEmptyState(BuildContext context) => const _EmptyPanelState(
    icon: Icons.link_off,
    title: 'No active connections',
    message: 'Open a host to create one.',
  );
}

class _ConnectionPreviewText extends StatelessWidget {
  const _ConnectionPreviewText({
    required this.endpoint,
    this.preview,
    this.windowTitle,
    this.iconName,
    this.workingDirectory,
    this.shellStatus,
    this.lastExitCode,
    this.terminalTheme,
  });

  final String endpoint;
  final String? preview;
  final String? windowTitle;
  final String? iconName;
  final Uri? workingDirectory;
  final TerminalShellStatus? shellStatus;
  final int? lastExitCode;
  final TerminalThemeData? terminalTheme;

  @override
  Widget build(BuildContext context) => ConnectionPreviewSnippet(
    endpoint: endpoint,
    preview: preview,
    windowTitle: windowTitle,
    iconName: iconName,
    workingDirectory: workingDirectory,
    shellStatus: shellStatus,
    lastExitCode: lastExitCode,
    terminalTheme: terminalTheme,
  );
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (primary) {
      return DecoratedBox(
        decoration: BoxDecoration(
          gradient: FluttyTheme.accentGradient,
          borderRadius: BorderRadius.circular(18),
          boxShadow: FluttyTheme.glowShadow(colorScheme.primary),
        ),
        child: FilledButton.icon(
          onPressed: onTap,
          icon: Icon(icon, size: 16),
          label: Text(label),
          style: FilledButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            textStyle: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }

    return TextButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16, color: colorScheme.onSurfaceVariant),
      label: Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _SmallIconButton extends StatelessWidget {
  const _SmallIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHigh.withAlpha(110),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: colorScheme.outlineVariant.withAlpha(120),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(icon, size: 16, color: colorScheme.onSurfaceVariant),
          ),
        ),
      ),
    );
  }
}

class _KeysPanel extends ConsumerWidget {
  const _KeysPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final keysAsync = ref.watch(allKeysProvider);

    return _PanelShell(
      title: 'SSH Keys',
      trailing: _ActionButton(
        icon: Icons.add,
        label: 'Add Key',
        onTap: () => context.push('/keys/add'),
        primary: true,
      ),
      child: keysAsync.when(
        loading: () =>
            const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (keys) => keys.isEmpty
            ? _buildEmptyState(context)
            : _buildKeysList(context, ref, keys),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) => _EmptyPanelState(
    icon: Icons.key_outlined,
    title: 'No SSH keys yet',
    message: 'Generate or import a key.',
    action: FilledButton.icon(
      onPressed: () => context.push('/keys/add'),
      icon: const Icon(Icons.add, size: 18),
      label: const Text('Add Key'),
    ),
  );

  Widget _buildKeysList(
    BuildContext context,
    WidgetRef ref,
    List<SshKey> keys,
  ) => ListView.builder(
    padding: const EdgeInsets.fromLTRB(0, 10, 0, 22),
    itemCount: keys.length,
    itemBuilder: (context, index) {
      final key = keys[index];
      return _KeyRow(sshKey: key);
    },
  );
}

class _KeyRow extends ConsumerWidget {
  const _KeyRow({required this.sshKey});

  final SshKey sshKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return _InteractiveGlassTile(
      onTap: () => _showKeyDetails(context),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF00C9FF).withAlpha(92),
                  colorScheme.surfaceContainerHigh.withAlpha(110),
                ],
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              _getKeyIcon(),
              size: 18,
              color: const Color(0xFF00C9FF),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sshKey.name,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  sshKey.keyType.toUpperCase(),
                  style: FluttyTheme.monoStyle.copyWith(
                    fontSize: 10.5,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _SmallIconButton(
                icon: Icons.save_alt,
                onTap: () => unawaited(_exportEncryptedFile(context, ref)),
              ),
              _SmallIconButton(
                icon: Icons.copy,
                onTap: () => _copyPublicKey(context),
              ),
              _SmallIconButton(
                icon: Icons.delete_outline,
                onTap: () => _confirmDelete(context, ref),
              ),
            ],
          ),
        ],
      ),
    );
  }

  IconData _getKeyIcon() {
    if (sshKey.keyType.toLowerCase().contains('ed25519')) {
      return Icons.enhanced_encryption;
    } else if (sshKey.keyType.toLowerCase().contains('rsa')) {
      return Icons.key;
    }
    return Icons.vpn_key;
  }

  void _copyPublicKey(BuildContext context) {
    Clipboard.setData(ClipboardData(text: sshKey.publicKey));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Public key copied')));
  }

  Future<void> _exportEncryptedFile(BuildContext context, WidgetRef ref) async {
    final isAuthorized = await authorizeSensitiveTransferExport(
      context: context,
      authService: ref.read(authServiceProvider),
      reason: 'Authenticate to export private key',
    );
    if (!context.mounted) {
      return;
    }
    if (!isAuthorized) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Authentication required for key export')),
      );
      return;
    }

    final transferPassphrase = await showTransferPassphraseDialog(
      context: context,
      title: 'Key transfer passphrase',
    );
    if (!context.mounted || transferPassphrase == null) {
      return;
    }

    final payload = await ref
        .read(secureTransferServiceProvider)
        .createKeyPayload(key: sshKey, transferPassphrase: transferPassphrase);

    if (!context.mounted) {
      return;
    }

    final defaultFileName = sanitizeTransferFileBaseName(
      'key-${sshKey.name.toLowerCase().replaceAll(' ', '-')}',
    );

    await saveTransferPayloadToFile(
      context: context,
      payload: payload,
      defaultFileName: defaultFileName,
    );
  }

  void _showKeyDetails(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        maxChildSize: 0.9,
        minChildSize: 0.3,
        expand: false,
        builder: (context, scrollController) => Padding(
          padding: const EdgeInsets.all(20),
          child: ListView(
            controller: scrollController,
            children: [
              // Handle bar
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colorScheme.outline,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(sshKey.name, style: theme.textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                sshKey.keyType.toUpperCase(),
                style: TextStyle(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 20),
              Text('Public Key', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colorScheme.outline.withAlpha(60)),
                ),
                child: SelectableText(
                  sshKey.publicKey,
                  style: FluttyTheme.monoStyle.copyWith(fontSize: 11),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => _copyPublicKey(context),
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('Copy Public Key'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Key'),
        content: Text('Delete "${sshKey.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if ((confirmed ?? false) && context.mounted) {
      await ref.read(keyRepositoryProvider).delete(sshKey.id);
    }
  }
}

/// Provider for all snippets as stream.
final _allSnippetsStreamProvider = StreamProvider<List<Snippet>>((ref) {
  final repo = ref.watch(snippetRepositoryProvider);
  return repo.watchAll();
});

/// Panel for displaying and managing snippets inline.
class _SnippetsPanel extends ConsumerWidget {
  const _SnippetsPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snippetsAsync = ref.watch(_allSnippetsStreamProvider);

    return _PanelShell(
      title: 'Snippets',
      trailing: _ActionButton(
        icon: Icons.add,
        label: 'Add Snippet',
        onTap: () => _showAddEditSnippetDialog(context, ref, null),
        primary: true,
      ),
      child: snippetsAsync.when(
        loading: () =>
            const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (snippets) => snippets.isEmpty
            ? _buildEmptyState(context, ref)
            : _buildSnippetsList(context, ref, snippets),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, WidgetRef ref) =>
      _EmptyPanelState(
        icon: Icons.code_outlined,
        title: 'No snippets yet',
        message: 'Save commands you use often.',
        action: FilledButton.icon(
          onPressed: () => _showAddEditSnippetDialog(context, ref, null),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Add Snippet'),
        ),
      );

  Widget _buildSnippetsList(
    BuildContext context,
    WidgetRef ref,
    List<Snippet> snippets,
  ) => ListView.builder(
    padding: const EdgeInsets.fromLTRB(0, 10, 0, 22),
    itemCount: snippets.length,
    itemBuilder: (context, index) {
      final snippet = snippets[index];
      return _SnippetRow(snippet: snippet);
    },
  );

  static Future<void> _showAddEditSnippetDialog(
    BuildContext context,
    WidgetRef ref,
    Snippet? existing,
  ) async {
    final nameController = TextEditingController(text: existing?.name ?? '');
    final commandController = TextEditingController(
      text: existing?.command ?? '',
    );
    final descriptionController = TextEditingController(
      text: existing?.description ?? '',
    );
    final formKey = GlobalKey<FormState>();

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: DraggableScrollableSheet(
          maxChildSize: 0.9,
          minChildSize: 0.5,
          initialChildSize: 0.7,
          expand: false,
          builder: (context, scrollController) => Form(
            key: formKey,
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.all(20),
              children: [
                // Handle bar
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.outline,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  existing == null ? 'Add Snippet' : 'Edit Snippet',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    hintText: 'Restart Docker',
                    prefixIcon: Icon(Icons.label),
                  ),
                  textInputAction: TextInputAction.next,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter a name';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Description (optional)',
                    hintText: 'What this snippet does',
                    prefixIcon: Icon(Icons.description),
                  ),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: commandController,
                  decoration: const InputDecoration(
                    labelText: 'Command',
                    hintText: 'docker restart {{container}}',
                    alignLabelWithHint: true,
                  ),
                  maxLines: 4,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter a command';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 8),
                Text(
                  'Use {{variable}} for substitution',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () {
                          if (formKey.currentState!.validate()) {
                            Navigator.pop(context, true);
                          }
                        },
                        child: Text(existing == null ? 'Add' : 'Save'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (result ?? false) {
      final repo = ref.read(snippetRepositoryProvider);
      final description = descriptionController.text.isEmpty
          ? null
          : descriptionController.text;

      if (existing != null) {
        await repo.update(
          existing.copyWith(
            name: nameController.text,
            command: commandController.text,
            description: drift.Value(description),
          ),
        );
      } else {
        await repo.insert(
          SnippetsCompanion.insert(
            name: nameController.text,
            command: commandController.text,
            description: drift.Value(description),
          ),
        );
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              existing == null ? 'Snippet added' : 'Snippet updated',
            ),
          ),
        );
      }
    }

    nameController.dispose();
    commandController.dispose();
    descriptionController.dispose();
  }
}

class _SnippetRow extends ConsumerWidget {
  const _SnippetRow({required this.snippet});

  final Snippet snippet;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return _InteractiveGlassTile(
      onTap: () => _copySnippet(context, ref),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  colorScheme.primary.withAlpha(92),
                  colorScheme.surfaceContainerHigh.withAlpha(110),
                ],
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(Icons.code, size: 18, color: colorScheme.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  snippet.name,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  snippet.command.replaceAll('\n', ' '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: FluttyTheme.monoStyle.copyWith(
                    fontSize: 10.5,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _SmallIconButton(
                icon: Icons.copy,
                onTap: () => _copySnippet(context, ref),
              ),
              _SmallIconButton(
                icon: Icons.edit_outlined,
                onTap: () => _SnippetsPanel._showAddEditSnippetDialog(
                  context,
                  ref,
                  snippet,
                ),
              ),
              _SmallIconButton(
                icon: Icons.delete_outline,
                onTap: () => _confirmDelete(context, ref),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _copySnippet(BuildContext context, WidgetRef ref) {
    Clipboard.setData(ClipboardData(text: snippet.command));
    unawaited(ref.read(snippetRepositoryProvider).incrementUsage(snippet.id));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Copied "${snippet.name}" to clipboard')),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Snippet'),
        content: Text('Delete "${snippet.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if ((confirmed ?? false) && context.mounted) {
      await ref.read(snippetRepositoryProvider).delete(snippet.id);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Deleted "${snippet.name}"')));
      }
    }
  }
}
