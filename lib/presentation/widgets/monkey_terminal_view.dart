import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ghostty_vte_flutter/ghostty_vte_flutter.dart';

import '../../domain/models/cell_offset.dart';
import '../../domain/models/terminal_theme.dart';

/// Terminal render padding.
///
/// Keep horizontal cutout insets in landscape, but avoid adding extra blank
/// rows at the bottom or side gutters in portrait.
EdgeInsets resolveTerminalRenderPadding(MediaQueryData mediaQuery) {
  final isLandscape = mediaQuery.size.width > mediaQuery.size.height;
  if (!isLandscape) {
    return EdgeInsets.zero;
  }
  return EdgeInsets.only(
    left: mediaQuery.padding.left,
    right: mediaQuery.padding.right,
  );
}

/// Thin Flutty terminal view wrapping [GhosttyTerminalView].
///
/// Exposes a subset of the legacy xterm-based `MonkeyTerminalView` API so
/// existing call sites continue to work after the Ghostty migration. Some
/// advanced hit-testing surfaces (`renderTerminal.getCellOffset` /
/// `renderTerminal.getOffset`) are preserved as thin stubs — callers that
/// depended on them for path-link overlays will return empty hit-test
/// results until they are reimplemented against Ghostty's render snapshot.
class MonkeyTerminalView extends StatefulWidget {
  /// Creates a new [MonkeyTerminalView].
  const MonkeyTerminalView(
    this.controller, {
    super.key,
    this.themeBundle,
    this.padding,
    this.scrollController,
    this.focusNode,
    this.autofocus = false,
    this.fontSize = 14,
    this.fontFamily,
    this.onTapUp,
    this.onDoubleTapDown,
    this.onSecondaryTapDown,
    this.onSecondaryTapUp,
    this.resolveLinkTap,
    this.onLinkTapDown,
    this.onLinkTap,
    this.onOpenHyperlink,
    this.onPasteText,
    this.onInsertText,
    this.readOnly = false,
    this.hardwareKeyboardOnly = false,
    this.simulateScroll = true,
    this.touchScrollToTerminal = false,
    this.backgroundOpacity = 1,
  });

  /// The underlying terminal controller that this widget renders.
  final GhosttyTerminalController controller;

  /// Optional theme bundle to drive the Ghostty view colors.
  final GhosttyThemeBundle? themeBundle;

  /// Padding around the inner terminal.
  final EdgeInsets? padding;

  /// Scroll controller for the inner scroll view.
  final ScrollController? scrollController;

  /// Focus node for the terminal.
  final FocusNode? focusNode;

  /// Whether to auto-request focus on insertion.
  final bool autofocus;

  /// Base monospace font size.
  final double fontSize;

  /// Optional font family.
  final String? fontFamily;

  /// Callback for tap-up events on the terminal.
  final void Function(TapUpDetails details, CellOffset offset)? onTapUp;

  /// Callback for double-tap-down events on the terminal.
  final void Function(TapDownDetails details, CellOffset offset)?
  onDoubleTapDown;

  /// Callback for secondary-tap-down events on the terminal.
  final void Function(TapDownDetails details, CellOffset offset)?
  onSecondaryTapDown;

  /// Callback for secondary-tap-up events on the terminal.
  final void Function(TapUpDetails details, CellOffset offset)?
  onSecondaryTapUp;

  /// Hyperlink resolver used by the legacy path-link pipeline.
  final String? Function(CellOffset offset)? resolveLinkTap;

  /// Invoked when the user presses down on a resolved link.
  final VoidCallback? onLinkTapDown;

  /// Invoked when the user taps a resolved link.
  final void Function(String uri)? onLinkTap;

  /// Invoked when the Ghostty view itself wants to open a hyperlink
  /// (used on desktop, driven by Ctrl/Cmd-click).
  final Future<void> Function(String uri)? onOpenHyperlink;

  /// Paste callback when external paste handling is required.
  final Future<void> Function()? onPasteText;

  /// Insert-text callback used by legacy desktop IME confirmation.
  final void Function(String text)? onInsertText;

  /// Whether the terminal should ignore keyboard input.
  final bool readOnly;

  /// Whether only hardware keyboard events should drive input (mobile).
  final bool hardwareKeyboardOnly;

  /// Whether synthetic scroll events should be delivered to alt-buffer apps.
  final bool simulateScroll;

  /// Whether touch scroll gestures should scroll the terminal.
  final bool touchScrollToTerminal;

  /// Background opacity multiplier.
  final double backgroundOpacity;

  @override
  State<MonkeyTerminalView> createState() => MonkeyTerminalViewState();
}

/// State for [MonkeyTerminalView].
class MonkeyTerminalViewState extends State<MonkeyTerminalView> {
  FocusNode? _ownedFocusNode;

  /// Focus node used for keyboard input.
  FocusNode get focusNode => widget.focusNode ?? _ownedFocusNode!;

  /// Lightweight render-surface stub that mirrors the small subset of the
  /// legacy xterm `RenderTerminal` API used by call sites.
  ///
  /// All hit-test methods return safe defaults; call sites that previously
  /// depended on exact cell coordinates should migrate to
  /// [GhosttyTerminalController.snapshot] over time.
  late final MonkeyTerminalRenderSurface renderTerminal =
      MonkeyTerminalRenderSurface(this);

  @override
  void initState() {
    super.initState();
    if (widget.focusNode == null) {
      _ownedFocusNode = FocusNode(debugLabel: 'MonkeyTerminalView');
    }
  }

  @override
  void didUpdateWidget(covariant MonkeyTerminalView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      if (widget.focusNode != null) {
        _ownedFocusNode?.dispose();
        _ownedFocusNode = null;
      } else {
        _ownedFocusNode ??= FocusNode(debugLabel: 'MonkeyTerminalView');
      }
    }
  }

  @override
  void dispose() {
    _ownedFocusNode?.dispose();
    super.dispose();
  }

  Future<void> _handleOpenHyperlink(String uri) async {
    widget.onLinkTap?.call(uri);
    if (widget.onOpenHyperlink != null) {
      await widget.onOpenHyperlink!(uri);
    }
  }

  Future<String?> _handlePaste() async {
    final override = widget.onPasteText;
    if (override != null) {
      await override();
      return null;
    }
    final data = await Clipboard.getData('text/plain');
    return data?.text;
  }

  @override
  Widget build(BuildContext context) {
    final theme =
        widget.themeBundle ??
        const GhosttyThemeBundle(
          foreground: Color(0xFFE6EDF3),
          background: Color(0xFF0A0F14),
          cursor: Color(0xFF9AD1C0),
          selection: Color(0x665DA9FF),
          palette: GhosttyTerminalPalette.xterm,
        );

    final view = GhosttyTerminalView(
      controller: widget.controller,
      focusNode: focusNode,
      autofocus: widget.autofocus,
      showHeader: false,
      fontSize: widget.fontSize,
      fontFamily: widget.fontFamily,
      padding: widget.padding ?? EdgeInsets.zero,
      backgroundColor: theme.background,
      foregroundColor: theme.foreground,
      cursorColor: theme.cursor,
      selectionColor: theme.selection,
      palette: theme.palette,
      onOpenHyperlink: _handleOpenHyperlink,
      onPasteRequest: _handlePaste,
    );

    Widget child = view;
    if (widget.backgroundOpacity < 1) {
      child = Opacity(opacity: widget.backgroundOpacity, child: child);
    }
    return child;
  }
}

/// Hit-test surface exposed by [MonkeyTerminalViewState].
///
/// Uses a [TextPainter] measurement of the configured monospace font to
/// convert between local widget coordinates and terminal cell positions.
/// The metrics intentionally match the defaults applied to
/// [GhosttyTerminalView] (line-height multiplier of 1.2, single-width
/// cells sized by 'M').
class MonkeyTerminalRenderSurface {
  /// Creates a new [MonkeyTerminalRenderSurface] bound to [_state].
  MonkeyTerminalRenderSurface(this._state);

  final MonkeyTerminalViewState _state;

  Size _cachedCellSize = const Size(8, 18);
  double _cachedCellSizeFor = 0;
  String? _cachedCellSizeFontFamily;

  /// Line height used by the legacy underline overlay.
  double get lineHeight => cellSize.height;

  /// Cell size used by hit-testing logic.
  Size get cellSize {
    final fontSize = _state.widget.fontSize;
    final fontFamily = _state.widget.fontFamily;
    if (_cachedCellSizeFor != fontSize ||
        _cachedCellSizeFontFamily != fontFamily) {
      _cachedCellSize = _measureCell(fontSize, fontFamily);
      _cachedCellSizeFor = fontSize;
      _cachedCellSizeFontFamily = fontFamily;
    }
    return _cachedCellSize;
  }

  /// Reported viewport size of the underlying render object, if any.
  Size get size {
    final renderObject = _state.context.findRenderObject();
    if (renderObject is RenderBox && renderObject.hasSize) {
      return renderObject.size;
    }
    return Size.zero;
  }

  /// Returns the Ghostty cell offset that contains [localPosition].
  CellOffset getCellOffset(Offset localPosition) {
    final cell = cellSize;
    if (cell.width <= 0 || cell.height <= 0) {
      return const CellOffset(0, 0);
    }
    final x = (localPosition.dx / cell.width).floor().clamp(
      0,
      _state.widget.controller.cols - 1,
    );
    final y = (localPosition.dy / cell.height).floor().clamp(
      0,
      _state.widget.controller.rows - 1,
    );
    return CellOffset(x, y);
  }

  /// Returns the local origin of the cell at [offset].
  Offset getOffset(CellOffset offset) {
    final cell = cellSize;
    return Offset(offset.x * cell.width, offset.y * cell.height);
  }

  /// Converts a local offset to a global offset via the render surface.
  Offset localToGlobal(Offset local, {RenderObject? ancestor}) {
    final renderObject = _state.context.findRenderObject();
    if (renderObject is RenderBox) {
      return renderObject.localToGlobal(local, ancestor: ancestor);
    }
    return local;
  }

  /// Converts a global offset to a local offset via the render surface.
  Offset globalToLocal(Offset global, {RenderObject? ancestor}) {
    final renderObject = _state.context.findRenderObject();
    if (renderObject is RenderBox) {
      return renderObject.globalToLocal(global, ancestor: ancestor);
    }
    return global;
  }

  Size _measureCell(double fontSize, String? fontFamily) {
    final painter = TextPainter(
      text: TextSpan(
        text: 'M',
        style: TextStyle(
          fontSize: fontSize,
          fontFamily: fontFamily,
          height: 1.2,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final height = painter.height;
    final width = painter.width;
    painter.dispose();
    return Size(width <= 0 ? fontSize * 0.6 : width, height);
  }
}
