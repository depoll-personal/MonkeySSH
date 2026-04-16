// Compatibility shim for the xterm → Ghostty VTE migration.
//
// Provides stand-in types that mirror a small portion of the legacy xterm
// API consumed by `terminal_screen.dart`, implemented on top of the
// Ghostty VT engine exposed through [GhosttyTerminalController.terminal].

import 'package:flutter/foundation.dart';
import 'package:ghostty_vte_flutter/ghostty_vte_flutter.dart';

import 'cell_offset.dart';

export 'cell_offset.dart';

/// Legacy xterm-compatible mouse-mode enum.
///
/// Derived from Ghostty's [VtMouseProtocolState.trackingMode].
enum MouseMode {
  /// No mouse reporting.
  none,

  /// Click-only mouse reporting.
  clickOnly,

  /// Button press + release with scroll.
  upDownScroll,

  /// Press / release / scroll, plus drag tracking.
  upDownScrollDrag,

  /// Any motion, plus the above.
  upDownScrollMove,
}

/// Extension that reports whether the mode covers scroll wheel reporting.
extension MouseModeReportScroll on MouseMode {
  /// Whether this mode reports scroll-wheel events.
  bool get reportScroll => this != MouseMode.none;
}

/// Legacy xterm-compatible mouse report wire format.
enum MouseReportMode {
  /// Default (X10) mouse report format.
  normal,

  /// UTF-8 mouse report format.
  utf8,

  /// SGR extended report format.
  sgr,

  /// urxvt mouse report format.
  urxvt,

  /// SGR pixel-coordinate report format.
  sgrPixels,
}

/// Mutable selection state shared between [MonkeyTerminalView] callbacks
/// (via `onSelectionChanged`) and call sites in `terminal_screen.dart`.
///
/// Ghostty's view renders its own selection overlay internally; this
/// controller caches the last reported selection as a [BufferRange] so the
/// surrounding app UI (copy / context-menu logic) can reason about it.
class LegacyTerminalSelectionController extends ChangeNotifier {
  BufferRange? _selection;

  /// The current selection range, or `null` when no selection is active.
  BufferRange? get selection => _selection;

  /// Clears any active selection.
  void clearSelection() {
    if (_selection == null) {
      return;
    }
    _selection = null;
    notifyListeners();
  }

  /// Replaces the current selection.
  void setSelection(BufferRange? range) {
    if (_selection == range) {
      return;
    }
    _selection = range;
    notifyListeners();
  }
}

/// Convenience accessors that mirror the subset of xterm's [Terminal] API
/// used by `terminal_screen.dart`, implemented against the Ghostty VT engine.
extension GhosttyTerminalCompat on GhosttyTerminalController {
  /// Whether the remote application has switched to the alternate screen.
  bool get isUsingAltBuffer {
    try {
      return !terminal.isPrimaryScreen;
    } on Object {
      return false;
    }
  }

  /// Current mouse tracking mode reported to the remote application.
  MouseMode get mouseMode {
    final state = _safeMouseProtocolState();
    if (state == null || !state.enabled) {
      return MouseMode.none;
    }
    switch (state.trackingMode) {
      case GhosttyMouseTrackingMode.GHOSTTY_MOUSE_TRACKING_X10:
        return MouseMode.clickOnly;
      case GhosttyMouseTrackingMode.GHOSTTY_MOUSE_TRACKING_NORMAL:
        return MouseMode.upDownScroll;
      case GhosttyMouseTrackingMode.GHOSTTY_MOUSE_TRACKING_BUTTON:
        return MouseMode.upDownScrollDrag;
      case GhosttyMouseTrackingMode.GHOSTTY_MOUSE_TRACKING_ANY:
        return MouseMode.upDownScrollMove;
      case GhosttyMouseTrackingMode.GHOSTTY_MOUSE_TRACKING_NONE:
      case null:
        return MouseMode.none;
    }
  }

  /// Current mouse report format.
  MouseReportMode get mouseReportMode {
    final state = _safeMouseProtocolState();
    if (state == null || !state.enabled) {
      return MouseReportMode.normal;
    }
    switch (state.format) {
      case GhosttyMouseFormat.GHOSTTY_MOUSE_FORMAT_SGR:
        return MouseReportMode.sgr;
      case GhosttyMouseFormat.GHOSTTY_MOUSE_FORMAT_UTF8:
        return MouseReportMode.utf8;
      case GhosttyMouseFormat.GHOSTTY_MOUSE_FORMAT_URXVT:
        return MouseReportMode.urxvt;
      case GhosttyMouseFormat.GHOSTTY_MOUSE_FORMAT_SGR_PIXELS:
        return MouseReportMode.sgrPixels;
      case GhosttyMouseFormat.GHOSTTY_MOUSE_FORMAT_X10:
      case null:
        return MouseReportMode.normal;
    }
  }

  /// Viewport width in cells. Mirrors xterm's `terminal.viewWidth`.
  int get viewWidth => cols;

  /// Viewport height in rows. Mirrors xterm's `terminal.viewHeight`.
  int get viewHeight => rows;

  /// Sends text as if the user typed it, forwarding to [write].
  void textInput(String text) {
    write(text);
  }

  /// Whether focus-in/out reporting (DEC mode 1004) is enabled.
  bool get reportFocusMode {
    try {
      return terminal.getMode(VtModes.focusEvent);
    } on Object {
      return false;
    }
  }

  /// Whether bracketed paste (DEC mode 2004) is enabled by the remote app.
  bool get bracketedPasteMode {
    try {
      return terminal.getMode(VtModes.bracketedPaste);
    } on Object {
      return false;
    }
  }

  /// Provides a read-only buffer view that emulates xterm's buffer API.
  LegacyBuffer get buffer => LegacyBuffer._(this);

  /// Pastes the provided text into the remote shell.
  ///
  /// Forwards to [GhosttyTerminalController.write]; Ghostty handles
  /// bracketed-paste framing internally when enabled by the remote app.
  void paste(String text) {
    write(text);
  }

  VtMouseProtocolState? _safeMouseProtocolState() {
    try {
      return terminal.mouseProtocolState;
    } on Object {
      return null;
    }
  }
}

/// Read-only buffer view that mimics a subset of xterm's `Buffer` API,
/// implemented against [GhosttyTerminalController.snapshot] and the
/// underlying [VtTerminal] for cursor/alt-screen information.
class LegacyBuffer {
  const LegacyBuffer._(this._controller);

  final GhosttyTerminalController _controller;

  /// The number of columns in the viewport.
  int get viewWidth => _controller.cols;

  /// The number of rows in the viewport.
  int get viewHeight => _controller.rows;

  /// Viewport height (rows). Mirrors xterm's `Buffer.height`.
  int get height => _controller.rows;

  /// Indexable view of buffer lines (including scrollback).
  LegacyBufferLines get lines => LegacyBufferLines._(_controller);

  /// Returns the plain text spanning [range].
  ///
  /// Walks the controller's styled snapshot between the begin and end cell
  /// offsets, concatenating line text and inserting newline separators
  /// where the source lines were not soft-wrapped.
  String getText(BufferRange range) {
    final snapshot = _controller.snapshot;
    final lines = snapshot.lines;
    if (lines.isEmpty) {
      return '';
    }
    final normalized = range.normalized;
    final startY = normalized.begin.y.clamp(0, lines.length - 1);
    final endY = normalized.end.y.clamp(0, lines.length - 1);
    if (startY > endY) {
      return '';
    }
    final buf = StringBuffer();
    for (var y = startY; y <= endY; y++) {
      final line = lines[y];
      final text = line.text;
      final isFirst = y == startY;
      final isLast = y == endY;
      final from = isFirst ? normalized.begin.x.clamp(0, text.length) : 0;
      final to = isLast
          ? normalized.end.x.clamp(from, text.length)
          : text.length;
      if (from < to) {
        buf.write(text.substring(from, to));
      }
      if (!isLast && !line.wrapContinuation) {
        buf.write('\n');
      }
    }
    return buf.toString();
  }

  /// Returns the line at absolute position [absY].
  BufferLine getLine(int absY) => lines[absY];

  /// Cursor Y position in the scrollback-inclusive buffer.
  int get absoluteCursorY {
    try {
      final snap = _controller.renderSnapshot;
      if (snap != null && snap.cursor.row != null) {
        return snap.cursor.row!;
      }
      return _controller.terminal.cursorY;
    } on Object {
      return 0;
    }
  }

  /// Cursor X position (column) in the current viewport.
  int get cursorX {
    try {
      return _controller.terminal.cursorX;
    } on Object {
      return 0;
    }
  }

  /// Cursor Y position (row) within the active viewport.
  int get cursorY {
    try {
      return _controller.terminal.cursorY;
    } on Object {
      return 0;
    }
  }
}

/// Indexable view of buffer lines that preserves xterm's `buffer.lines[idx]`
/// access pattern.
class LegacyBufferLines {
  const LegacyBufferLines._(this._controller);

  final GhosttyTerminalController _controller;

  /// Total line count including scrollback.
  int get length => _controller.lineCount;

  /// Returns the line at [index].
  BufferLine operator [](int index) {
    final snap = _controller.snapshot;
    if (index < 0 || index >= snap.lines.length) {
      return const BufferLine();
    }
    return BufferLine._(snap.lines[index]);
  }
}

/// Stub for xterm's [BufferLine].
///
/// Wraps a [GhosttyTerminalLine] when available; otherwise returns empty
/// values. All accessors preserve the legacy API surface while the call
/// sites migrate to Ghostty's snapshot model.
@immutable
class BufferLine {
  /// Creates an empty [BufferLine] stub.
  const BufferLine() : _line = null;

  const BufferLine._(GhosttyTerminalLine line) : _line = line;

  final GhosttyTerminalLine? _line;

  /// Returns the plain text of the line.
  String getText([int? start, int? end]) {
    final line = _line;
    if (line == null) {
      return '';
    }
    final text = line.text;
    final s = start ?? 0;
    final e = end ?? text.length;
    if (s < 0 || s >= text.length) {
      return '';
    }
    return text.substring(s, e.clamp(s, text.length));
  }

  /// Whether this line soft-wraps into the next.
  bool get isWrapped => _line?.wrapContinuation ?? false;

  /// Returns the Unicode code point at column [x].
  ///
  /// Stub returns 0 when the line is empty.
  int getCodePoint(int x) {
    final line = _line;
    if (line == null) {
      return 0;
    }
    final text = line.text;
    if (x < 0 || x >= text.length) {
      return 0;
    }
    return text.codeUnitAt(x);
  }

  /// Returns the character width at column [x].
  ///
  /// Stub: always returns 1 (single-width cell).
  int getWidth(int x) => 1;
}

/// Stub for xterm's [BufferRange].
@immutable
class BufferRange {
  /// Creates a new [BufferRange] stub.
  const BufferRange(this.begin, this.end);

  /// Start of the range.
  final CellOffset begin;

  /// End of the range (exclusive).
  final CellOffset end;

  /// Returns a normalized copy where [begin] <= [end].
  BufferRange get normalized {
    final startsFirst =
        begin.y < end.y || (begin.y == end.y && begin.x <= end.x);
    if (startsFirst) {
      return this;
    }
    return BufferRange(end, begin);
  }
}

/// Stub for xterm's [TerminalStyle].
///
/// Ghostty applies font metrics through [GhosttyTerminalView] widget props,
/// so most style fields are unused in the migrated code. This stub preserves
/// the positional call sites.
@immutable
class TerminalStyle {
  /// Creates a new [TerminalStyle].
  const TerminalStyle({
    this.fontSize = 14,
    this.fontFamily,
    this.fontFamilyFallback,
    this.height = 1.2,
  });

  /// Builds a [TerminalStyle] from a Flutter [TextStyle]-like object.
  ///
  /// Only the numeric font size and family information is preserved.
  // ignore: prefer_constructors_over_static_methods
  static TerminalStyle fromTextStyle(Object? style) => const TerminalStyle();

  /// Base font size in logical pixels.
  final double fontSize;

  /// Optional monospace font family.
  final String? fontFamily;

  /// Optional fallback family list.
  final List<String>? fontFamilyFallback;

  /// Line-height multiplier.
  final double height;

  /// Returns a copy of this style with the provided overrides.
  TerminalStyle copyWith({
    double? fontSize,
    String? fontFamily,
    List<String>? fontFamilyFallback,
    double? height,
  }) => TerminalStyle(
    fontSize: fontSize ?? this.fontSize,
    fontFamily: fontFamily ?? this.fontFamily,
    fontFamilyFallback: fontFamilyFallback ?? this.fontFamilyFallback,
    height: height ?? this.height,
  );

  /// Returns a textual representation suitable for the legacy call site.
  ///
  /// Stub: returns `null`. The Ghostty view does not accept a [TextStyle].
  Object? toTextStyle() => null;
}
