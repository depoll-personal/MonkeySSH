import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../app/theme.dart';
import '../../domain/services/ssh_service.dart';

/// Tab bar for managing multiple terminal sessions.
class TerminalTabBar extends ConsumerWidget {
  /// Creates a new [TerminalTabBar].
  const TerminalTabBar({
    required this.activeHostId,
    required this.onTabSelected,
    required this.onTabClosed,
    required this.onNewTab,
    super.key,
  });

  /// Currently active host ID.
  final int? activeHostId;

  /// Callback when a tab is selected.
  final void Function(int hostId) onTabSelected;

  /// Callback when a tab is closed.
  final void Function(int hostId) onTabClosed;

  /// Callback to add a new tab.
  final VoidCallback onNewTab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionStates = ref.watch(activeSessionsProvider);
    final sshService = ref.read(sshServiceProvider);
    final colorScheme = Theme.of(context).colorScheme;

    if (sessionStates.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: FluttyGlassSurface(
        borderRadius: BorderRadius.circular(26),
        blurSigma: 18,
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        child: Row(
          children: [
            Expanded(
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: sessionStates.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final hostId = sessionStates.keys.elementAt(index);
                  final connectionState = sessionStates[hostId]!;
                  final session = sshService.getSession(hostId);
                  final isActive = hostId == activeHostId;
                  final isConnected =
                      connectionState == SshConnectionState.connected;

                  return _TerminalTab(
                    label: session?.config.hostname ?? 'Host $hostId',
                    isActive: isActive,
                    isConnected: isConnected,
                    onTap: () => onTabSelected(hostId),
                    onClose: () => onTabClosed(hostId),
                  );
                },
              ),
            ),
            const SizedBox(width: 10),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: FluttyTheme.accentGradient,
                borderRadius: BorderRadius.circular(18),
                boxShadow: FluttyTheme.glowShadow(colorScheme.primary),
              ),
              child: IconButton(
                icon: const Icon(Icons.add_rounded, size: 18),
                onPressed: onNewTab,
                tooltip: 'New connection',
                visualDensity: VisualDensity.compact,
                style: IconButton.styleFrom(
                  foregroundColor: colorScheme.onPrimary,
                  padding: const EdgeInsets.all(10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TerminalTab extends StatelessWidget {
  const _TerminalTab({
    required this.label,
    required this.isActive,
    required this.isConnected,
    required this.onTap,
    required this.onClose,
  });

  final String label;
  final bool isActive;
  final bool isConnected;
  final VoidCallback onTap;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final activeBackground = isActive
        ? LinearGradient(
            colors: [
              colorScheme.primary.withAlpha(72),
              colorScheme.secondary.withAlpha(44),
            ],
          )
        : LinearGradient(
            colors: [
              Colors.white.withAlpha(
                theme.brightness == Brightness.dark ? 6 : 96,
              ),
              Colors.white.withAlpha(
                theme.brightness == Brightness.dark ? 2 : 64,
              ),
            ],
          );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          constraints: const BoxConstraints(minWidth: 120, maxWidth: 220),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            gradient: activeBackground,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isActive
                  ? colorScheme.primary.withAlpha(110)
                  : colorScheme.outlineVariant.withAlpha(160),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isConnected
                      ? colorScheme.primary
                      : colorScheme.tertiary.withAlpha(220),
                  boxShadow: isConnected
                      ? [
                          BoxShadow(
                            color: colorScheme.primary.withAlpha(120),
                            blurRadius: 10,
                            spreadRadius: 1,
                          ),
                        ]
                      : null,
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: isActive ? FontWeight.w700 : FontWeight.w600,
                    color: isActive
                        ? colorScheme.onSurface
                        : colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onClose,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      Icons.close_rounded,
                      size: 14,
                      color: isActive
                          ? colorScheme.onSurface
                          : colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Provider for the active tab's host ID.
final activeTabProvider = StateProvider<int?>((ref) => null);
