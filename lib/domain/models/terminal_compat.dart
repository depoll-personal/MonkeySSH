// Compatibility shim for the xterm → Ghostty VTE migration.
//
// Provides minimal stand-in types and helpers for the legacy xterm API
// surface so existing call sites in terminal_screen.dart continue to
// type-check while path-link / mouse-mode / buffer access is being
// reimplemented against the Ghostty snapshot API.
//
// TODO(ghostty-migration): replace these stubs with real Ghostty-backed
// equivalents or refactor call sites to use GhosttyTerminalController
// snapshot APIs directly.

import 'package:flutter/foundation.dart';
import 'package:ghostty_vte_flutter/ghostty_vte_flutter.dart';

import 'cell_offset.dart';

export 'cell_offset.dart';

/// Stub for xterm's mouse-mode enum.
///
/// Ghostty tracks mouse reporting via [GhosttyMouseTrackingMode]; until that
/// is surfaced through the controller, we expose a simplified four-value
/// enum that preserves the downstream switch statements.
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

/// Stub for xterm's mouse report wire format.
enum MouseReportMode {
  /// Default mouse report format.
  normal,

  /// SGR extended report format.
  sgr,
}

/// Legacy stub replacement for xterm's [TerminalController].
///
/// Ghostty renders its own selection overlay and does not expose selection
/// state through the controller yet. Call sites use this class as a
/// bookmark for the selection / clear-selection operations that need to
/// migrate onto [GhosttyTerminalController] or [GhosttyTerminalView]
/// callbacks.
// TODO(ghostty-migration): replace with real selection state once Ghostty
// surfaces it.
class LegacyTerminalSelectionController extends ChangeNotifier {
  /// The current selection range. Always `null` for now.
  BufferRange? get selection => null;

  /// No-op hook for xterm's `clearSelection` API.
  void clearSelection() {}

  /// No-op hook for xterm's `setSelection` API.
  void setSelection(BufferRange? range) {}
}

/// Convenience accessors for Ghostty that mirror xterm's [Terminal] API in
/// the places touched by terminal_screen.dart.
///
/// Until feature-parity wrappers land, these return safe defaults. Callers
/// are marked with `// TODO(ghostty-migration):` comments at the use site.
extension GhosttyTerminalCompat on GhosttyTerminalController {
  /// Whether the remote application has switched to the alternate screen.
  ///
  /// Stub: always returns `false`. Ghostty tracks this internally but does
  /// not expose it via the public controller yet.
  bool get isUsingAltBuffer => false;

  /// Current mouse tracking mode reported to the remote application.
  ///
  /// Stub: always returns [MouseMode.none].
  MouseMode get mouseMode => MouseMode.none;

  /// Current mouse report format.
  MouseReportMode get mouseReportMode => MouseReportMode.normal;

  /// Legacy no-op retained for hit-test call sites during the migration.
  // TODO(ghostty-migration): remove when path-link hit testing is migrated.
  int get viewWidth => cols;

  /// Legacy no-op retained for hit-test call sites during the migration.
  int get viewHeight => rows;

  /// Sends text as if the user typed it.
  ///
  /// Forwards to [GhosttyTerminalController.write].
  void textInput(String text) {
    write(text);
  }

  /// Whether focus-in/out reporting is active.
  ///
  /// Stub: always `false`. Focus events are not yet piped through Ghostty.
  bool get reportFocusMode => false;

  /// Whether bracketed paste is enabled in the remote application.
  ///
  /// Stub: always `false`.
  bool get bracketedPasteMode => false;

  /// Provides access to a buffer view that emulates xterm's buffer API.
  LegacyBuffer get buffer => LegacyBuffer._(this);

  /// Legacy setter for xterm's `onOutput` callback.
  ///
  /// Ghostty routes output via `attachExternalTransport`; this setter is a
  /// no-op and retained only for call-site compatibility.
  // ignore: avoid_setters_without_getters
  set onOutput(void Function(String)? callback) {}

  /// Legacy setter for xterm's `onResize` callback.
  // ignore: avoid_setters_without_getters
  set onResize(void Function(int, int, int, int)? callback) {}

  /// Pastes the provided text into the remote shell.
  ///
  /// Forwards to [GhosttyTerminalController.write]; Ghostty handles
  /// bracketed-paste mode internally when enabled by the remote application.
  void paste(String text) {
    write(text);
  }
}

/// Read-only buffer view that mimics a subset of xterm's `Buffer` API.
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
  /// Stub: Ghostty does not expose range-based extraction via the
  /// controller yet, so this returns an empty string and callers should
  /// guard against that until a real implementation lands.
  // TODO(ghostty-migration): implement range extraction via snapshot.
  String getText(BufferRange range) => '';

  /// Returns the line at absolute position [absY].
  BufferLine getLine(int absY) => lines[absY];

  /// Stub cursor Y position (absolute).
  int get absoluteCursorY => 0;

  /// Stub cursor X position.
  int get cursorX => 0;

  /// Stub cursor Y position (viewport relative).
  int get cursorY => 0;
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
