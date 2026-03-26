import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../domain/models/terminal_theme.dart';
import '../../domain/models/terminal_themes.dart';
import '../../domain/services/settings_service.dart';
import '../../domain/services/ssh_service.dart';

/// Resolves the terminal theme that should be reflected in a preview chip.
TerminalThemeData resolveConnectionPreviewTheme({
  required Brightness brightness,
  required TerminalThemeSettings themeSettings,
  required Iterable<TerminalThemeData> availableThemes,
  String? lightThemeId,
  String? darkThemeId,
}) {
  final isDark = brightness == Brightness.dark;
  final themeLookup = {for (final theme in availableThemes) theme.id: theme};
  final preferredThemeId = isDark
      ? darkThemeId ?? themeSettings.darkThemeId
      : lightThemeId ?? themeSettings.lightThemeId;

  return themeLookup[preferredThemeId] ??
      TerminalThemes.getById(preferredThemeId) ??
      (isDark ? TerminalThemes.midnightPurple : TerminalThemes.cleanWhite);
}

/// Fallback status text for a connection preview with no terminal output yet.
String fallbackConnectionPreviewStatus(SshConnectionState state) =>
    switch (state) {
      SshConnectionState.connecting => 'Connecting…',
      SshConnectionState.authenticating => 'Authenticating…',
      SshConnectionState.error => 'Connection failed',
      SshConnectionState.reconnecting => 'Reconnecting…',
      _ => 'Waiting for terminal output…',
    };

/// Builds a stacked preview entry for a connection.
ConnectionPreviewStackEntry buildConnectionPreviewStackEntry({
  required int connectionId,
  required SshConnectionState state,
  required Brightness brightness,
  required TerminalThemeSettings themeSettings,
  required Iterable<TerminalThemeData> availableThemes,
  String? preview,
  String? windowTitle,
  String? iconName,
  Uri? workingDirectory,
  TerminalShellStatus? shellStatus,
  int? lastExitCode,
  String? hostLightThemeId,
  String? hostDarkThemeId,
  String? connectionLightThemeId,
  String? connectionDarkThemeId,
}) {
  final resolvedWindowTitle = windowTitle?.trim();
  final resolvedIconName = iconName?.trim();
  final titleSegments = <String>['Connection #$connectionId'];
  if ((resolvedIconName ?? '').isNotEmpty) {
    titleSegments.add(resolvedIconName!);
  }
  if ((resolvedWindowTitle ?? '').isNotEmpty) {
    titleSegments.add(resolvedWindowTitle!);
  }
  final resolvedPreview = preview?.trim();
  final workingDirectoryLabel = formatTerminalWorkingDirectoryLabel(
    workingDirectory,
  );
  final shellStatusLabel = describeTerminalShellStatus(
    shellStatus,
    lastExitCode: lastExitCode,
  );
  final metadataSegments = <String>[];
  if ((workingDirectoryLabel ?? '').isNotEmpty) {
    metadataSegments.add(workingDirectoryLabel!);
  }
  if ((shellStatusLabel ?? '').isNotEmpty) {
    metadataSegments.add(shellStatusLabel!);
  }
  final body = [
    if (metadataSegments.isNotEmpty) metadataSegments.join(' • '),
    if (resolvedPreview == null || resolvedPreview.isEmpty)
      fallbackConnectionPreviewStatus(state)
    else
      resolvedPreview,
  ].join('\n');

  return ConnectionPreviewStackEntry(
    title: titleSegments.join(' • '),
    body: body,
    terminalTheme: resolveConnectionPreviewTheme(
      brightness: brightness,
      themeSettings: themeSettings,
      availableThemes: availableThemes,
      lightThemeId: connectionLightThemeId ?? hostLightThemeId,
      darkThemeId: connectionDarkThemeId ?? hostDarkThemeId,
    ),
  );
}

/// Renders connection metadata with a visually distinct live terminal preview.
class ConnectionPreviewSnippet extends StatelessWidget {
  /// Creates a [ConnectionPreviewSnippet].
  const ConnectionPreviewSnippet({
    required this.endpoint,
    this.preview,
    this.windowTitle,
    this.iconName,
    this.workingDirectory,
    this.shellStatus,
    this.lastExitCode,
    this.endpointStyle,
    this.terminalTheme,
    this.showEndpoint = true,
    this.previewMaxLines = 5,
    super.key,
  });

  /// Endpoint or connection metadata shown above the preview.
  final String endpoint;

  /// Latest terminal preview text, when available.
  final String? preview;

  /// Latest remote window title, when available.
  final String? windowTitle;

  /// Latest remote icon name, when available.
  final String? iconName;

  /// Latest working-directory URI, when available.
  final Uri? workingDirectory;

  /// Latest shell integration status, when available.
  final TerminalShellStatus? shellStatus;

  /// Latest command exit code emitted through shell integration.
  final int? lastExitCode;

  /// Optional style override for the endpoint metadata.
  final TextStyle? endpointStyle;

  /// Terminal theme used to tint the preview surface.
  final TerminalThemeData? terminalTheme;

  /// Whether to render the endpoint metadata line above the preview.
  final bool showEndpoint;

  /// Maximum number of preview lines to render before truncating.
  final int previewMaxLines;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final previewText = preview?.trim();
    final resolvedWindowTitle = windowTitle?.trim();
    final resolvedIconName = iconName?.trim();
    final workingDirectoryLabel = formatTerminalWorkingDirectoryLabel(
      workingDirectory,
    );
    final shellStatusLabel = describeTerminalShellStatus(
      shellStatus,
      lastExitCode: lastExitCode,
    );
    final previewTheme = terminalTheme;
    final previewBackground = _previewSurfaceTint(
      colorScheme: colorScheme,
      previewTheme: previewTheme,
      brightness: theme.brightness,
    );
    final previewTextColor =
        previewTheme?.foreground.withAlpha(235) ?? colorScheme.onSurfaceVariant;
    final previewBorderColor = Color.alphaBlend(
      (previewTheme?.cursor ?? colorScheme.primary).withAlpha(38),
      colorScheme.outlineVariant.withAlpha(210),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showEndpoint) Text(endpoint, style: endpointStyle),
        if (resolvedIconName != null && resolvedIconName.isNotEmpty) ...[
          if (showEndpoint) const SizedBox(height: 3),
          Text(
            resolvedIconName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        if (resolvedWindowTitle != null && resolvedWindowTitle.isNotEmpty) ...[
          if (showEndpoint || (resolvedIconName?.isNotEmpty ?? false))
            const SizedBox(height: 3),
          Text(
            resolvedWindowTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: previewTextColor,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
        if ((workingDirectoryLabel?.isNotEmpty ?? false) ||
            (shellStatusLabel?.isNotEmpty ?? false)) ...[
          if (showEndpoint ||
              (resolvedIconName?.isNotEmpty ?? false) ||
              (resolvedWindowTitle?.isNotEmpty ?? false))
            const SizedBox(height: 3),
          Text(
            [
              if ((workingDirectoryLabel ?? '').isNotEmpty)
                workingDirectoryLabel!,
              if ((shellStatusLabel ?? '').isNotEmpty) shellStatusLabel!,
            ].join(' • '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        if (previewText != null && previewText.isNotEmpty) ...[
          if (showEndpoint ||
              (resolvedIconName?.isNotEmpty ?? false) ||
              (resolvedWindowTitle?.isNotEmpty ?? false) ||
              (workingDirectoryLabel?.isNotEmpty ?? false) ||
              (shellStatusLabel?.isNotEmpty ?? false))
            const SizedBox(height: 8),
          FluttyGlassSurface(
            borderRadius: BorderRadius.circular(18),
            blurSigma: 14,
            tintColor: previewBackground,
            borderColor: previewBorderColor,
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    for (final color in [
                      colorScheme.error.withAlpha(210),
                      colorScheme.tertiary.withAlpha(220),
                      (previewTheme?.cursor ?? colorScheme.primary).withAlpha(
                        220,
                      ),
                    ]) ...[
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: color,
                        ),
                      ),
                      const SizedBox(width: 5),
                    ],
                    const Spacer(),
                    Text(
                      'LIVE PREVIEW',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: previewTextColor.withAlpha(180),
                        letterSpacing: 1.1,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  previewText,
                  maxLines: previewMaxLines,
                  overflow: TextOverflow.ellipsis,
                  style: FluttyTheme.monoStyle.copyWith(
                    fontSize: 9.5,
                    color: previewTextColor,
                    height: 1.32,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Data for a single card in a stacked connection preview.
class ConnectionPreviewStackEntry {
  /// Creates a [ConnectionPreviewStackEntry].
  const ConnectionPreviewStackEntry({
    required this.title,
    required this.body,
    this.terminalTheme,
  });

  /// Short title shown at the top of the stacked card.
  final String title;

  /// Main preview or status text shown inside the card.
  final String body;

  /// Terminal theme used to tint the preview surface.
  final TerminalThemeData? terminalTheme;
}

/// Renders one or more connection preview cards in a visibly offset stack.
class ConnectionPreviewStack extends StatelessWidget {
  /// Creates a [ConnectionPreviewStack].
  const ConnectionPreviewStack({
    required this.entries,
    this.cardHeight = 84,
    this.verticalOffset = 16,
    this.horizontalOffset = 12,
    super.key,
  });

  /// Cards to render in the stack, ordered from oldest to newest.
  final List<ConnectionPreviewStackEntry> entries;

  /// Height of each stacked preview card.
  final double cardHeight;

  /// Vertical offset applied between stacked cards.
  final double verticalOffset;

  /// Horizontal offset applied between stacked cards.
  final double horizontalOffset;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const SizedBox.shrink();
    }

    final stackHeight = cardHeight + ((entries.length - 1) * verticalOffset);

    return SizedBox(
      width: double.infinity,
      height: stackHeight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxHorizontalInset = (entries.length - 1) * horizontalOffset;
          final cardWidth = constraints.maxWidth > maxHorizontalInset
              ? constraints.maxWidth - maxHorizontalInset
              : 0.0;

          return Stack(
            clipBehavior: Clip.none,
            children: [
              for (var index = 0; index < entries.length; index++)
                Positioned(
                  top: index * verticalOffset,
                  left: index * horizontalOffset,
                  width: cardWidth,
                  child: _ConnectionPreviewStackCard(
                    entry: entries[index],
                    height: cardHeight,
                    opacity: index == entries.length - 1
                        ? 1
                        : 0.92 - ((entries.length - index - 2) * 0.06),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _ConnectionPreviewStackCard extends StatelessWidget {
  const _ConnectionPreviewStackCard({
    required this.entry,
    required this.height,
    required this.opacity,
  });

  final ConnectionPreviewStackEntry entry;
  final double height;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final previewTheme = entry.terminalTheme;
    final backgroundColor = _previewSurfaceTint(
      colorScheme: colorScheme,
      previewTheme: previewTheme,
      brightness: theme.brightness,
    );
    final borderColor = Color.alphaBlend(
      (previewTheme?.cursor ?? colorScheme.primary).withAlpha(42),
      colorScheme.outlineVariant.withAlpha(210),
    );
    final textColor =
        previewTheme?.foreground.withAlpha(232) ?? colorScheme.onSurfaceVariant;

    return Opacity(
      opacity: opacity.clamp(0.72, 1).toDouble(),
      child: FluttyGlassSurface(
        borderRadius: BorderRadius.circular(18),
        blurSigma: 16,
        tintColor: backgroundColor,
        borderColor: borderColor,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: SizedBox(
          height: height - 20,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: (previewTheme?.cursor ?? colorScheme.primary)
                          .withAlpha(220),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      entry.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: textColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Text(
                  entry.body,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: FluttyTheme.monoStyle.copyWith(
                    fontSize: 9,
                    color: textColor,
                    height: 1.28,
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

Color _previewSurfaceTint({
  required ColorScheme colorScheme,
  required TerminalThemeData? previewTheme,
  required Brightness brightness,
}) {
  final isDark = brightness == Brightness.dark;
  if (previewTheme == null) {
    return isDark
        ? colorScheme.surfaceContainerHigh.withAlpha(182)
        : Colors.white.withAlpha(204);
  }

  return Color.alphaBlend(
    previewTheme.background.withAlpha(previewTheme.isDark ? 136 : 72),
    isDark
        ? colorScheme.surfaceContainerHigh.withAlpha(176)
        : Colors.white.withAlpha(210),
  );
}
