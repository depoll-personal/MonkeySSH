import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:ghostty_vte_flutter/ghostty_vte_flutter.dart';

import '../models/cell_offset.dart';

/// Tracks OSC 8 terminal hyperlinks so taps can open links whose labels do
/// not visibly contain the destination URL.
///
/// The Ghostty VTE 0.1.2 snapshot API does not expose hyperlink URIs on
/// formatted output, so this tracker runs its own lightweight OSC 8 scanner
/// over the raw byte stream. It records every `(label, uri)` pair observed
/// between `ESC ] 8 ; params ; URI ST` and the matching terminator, then
/// answers [resolveLinkAt] by searching the controller's current terminal
/// snapshot for an occurrence of the stored label that covers the requested
/// cell. Label-based lookup keeps resolution working across terminal reflow.
class TerminalHyperlinkTracker {
  GhosttyTerminalController? _controller;

  final List<_HyperlinkSpan> _spans = <_HyperlinkSpan>[];

  _OscState _oscState = _OscState.text;
  final BytesBuilder _oscBuffer = BytesBuilder(copy: false);

  String? _openUri;
  final StringBuffer _openLabel = StringBuffer();

  static const int _esc = 0x1B;
  static const int _bel = 0x07;
  static const int _csi = 0x5B;
  static const int _oscIntroducer = 0x5D;
  static const int _st2 = 0x5C;
  static const int _lf = 0x0A;

  static const int _maxSpans = 1024;
  static const int _maxLabelBytes = 2048;

  /// Attaches this tracker to [controller].
  ///
  /// Reattaching to the same controller is a no-op.
  void attach(GhosttyTerminalController controller) {
    if (identical(_controller, controller)) {
      return;
    }
    _controller = controller;
  }

  /// Clears any accumulated state.
  ///
  /// Pass `keepControllerReference: false` to also detach the associated
  /// [GhosttyTerminalController].
  void reset({bool keepControllerReference = true}) {
    _spans.clear();
    _oscBuffer.clear();
    _oscState = _OscState.text;
    _openUri = null;
    _openLabel.clear();
    if (!keepControllerReference) {
      _controller = null;
    }
  }

  /// Retained for API compatibility with the legacy xterm-backed tracker.
  ///
  /// Ghostty decodes OSC sequences natively and the terminal controller's
  /// OSC stream parser forwards them to the SSH service. This tracker
  /// consumes OSC 8 via [observeBytes] instead; [handlePrivateOsc] is a
  /// no-op.
  void handlePrivateOsc(String code, List<String> args) {}

  /// Scans [bytes] for OSC 8 sequences, accumulating `(label, uri)` spans.
  ///
  /// Call this with the same byte stream that is fed to
  /// [GhosttyTerminalController.appendOutputBytes] so the tracker can
  /// correlate hyperlinks with rendered cells.
  void observeBytes(List<int> bytes) {
    for (var i = 0; i < bytes.length; i++) {
      _consumeByte(bytes[i]);
    }
  }

  /// Resolves the hyperlink at [offset], if the cell at that row/column is
  /// covered by the label of a tracked OSC 8 hyperlink.
  String? resolveLinkAt(CellOffset offset) {
    final controller = _controller;
    if (controller == null) {
      return null;
    }
    final snapshot = controller.snapshot;
    final lines = snapshot.lines;
    if (offset.y < 0 || offset.y >= lines.length) {
      return null;
    }
    if (lines[offset.y].text.isEmpty) {
      return null;
    }

    // Build the logical (unwrapped) row that contains [offset.y], collecting
    // physical-row segments so we can map matches back to cell coordinates.
    var start = offset.y;
    while (start > 0 && lines[start].wrapContinuation) {
      start--;
    }
    var end = start;
    while (end < lines.length - 1 && lines[end].wrap) {
      end++;
    }
    final segments = <_LineSegment>[];
    final buf = StringBuffer();
    for (var y = start; y <= end; y++) {
      final text = lines[y].text;
      final segmentStart = buf.length;
      buf.write(text);
      segments.add(
        _LineSegment(row: y, start: segmentStart, length: text.length),
      );
    }
    final logical = buf.toString();
    if (logical.isEmpty) {
      return null;
    }

    // Iterate spans in reverse so the most recently observed URI wins for
    // labels redrawn in place.
    for (var s = _spans.length - 1; s >= 0; s--) {
      final span = _spans[s];
      if (span.label.isEmpty) {
        continue;
      }
      var idx = logical.indexOf(span.label);
      while (idx >= 0) {
        final matchEnd = idx + span.label.length;
        // Locate the segment covering [offset.y, offset.x] in logical space.
        for (final segment in segments) {
          if (segment.row != offset.y) {
            continue;
          }
          final logicalX = segment.start + offset.x;
          if (logicalX >= idx && logicalX < matchEnd) {
            return span.uri;
          }
        }
        idx = logical.indexOf(span.label, idx + 1);
      }
    }
    return null;
  }

  /// Number of tracked OSC 8 hyperlinks currently retained in memory.
  @visibleForTesting
  int get trackedHyperlinkCount => _spans.length;

  void _consumeByte(int b) {
    switch (_oscState) {
      case _OscState.text:
        if (b == _esc) {
          _oscState = _OscState.escape;
          return;
        }
        _appendLabelByte(b);
      case _OscState.escape:
        if (b == _oscIntroducer) {
          _oscBuffer.clear();
          _oscState = _OscState.oscBody;
        } else if (b == _csi) {
          _oscState = _OscState.csiBody;
        } else if (b == _esc) {
          // Stay in escape.
        } else {
          _oscState = _OscState.text;
        }
      case _OscState.oscBody:
        if (b == _bel) {
          _dispatchOsc();
          _oscState = _OscState.text;
        } else if (b == _esc) {
          _oscState = _OscState.oscStPending;
        } else {
          _oscBuffer.addByte(b);
        }
      case _OscState.oscStPending:
        if (b == _st2 || b == _bel) {
          _dispatchOsc();
          _oscState = _OscState.text;
        } else if (b == _esc) {
          // Stay pending.
        } else {
          _oscBuffer
            ..addByte(_esc)
            ..addByte(b);
          _oscState = _OscState.oscBody;
        }
      case _OscState.csiBody:
        if (b >= 0x40 && b <= 0x7E) {
          _oscState = _OscState.text;
        }
    }
  }

  void _appendLabelByte(int b) {
    if (_openUri == null) {
      return;
    }
    if (b == _lf || b == 0x0D) {
      return;
    }
    if (b < 0x20 && b != 0x09) {
      return;
    }
    if (_openLabel.length >= _maxLabelBytes) {
      return;
    }
    _openLabel.writeCharCode(b);
  }

  void _dispatchOsc() {
    final bytes = _oscBuffer.takeBytes();
    if (bytes.isEmpty) {
      return;
    }
    final text = _safeDecode(bytes);
    final semi = text.indexOf(';');
    final code = semi < 0 ? text : text.substring(0, semi);
    if (code != '8') {
      return;
    }
    final payload = semi < 0 ? '' : text.substring(semi + 1);
    final paramEnd = payload.indexOf(';');
    final uri = paramEnd < 0 ? '' : payload.substring(paramEnd + 1);

    _closeOpenSpan();
    if (uri.isNotEmpty) {
      _openUri = uri;
      _openLabel.clear();
    }
  }

  void _closeOpenSpan() {
    final uri = _openUri;
    if (uri == null) {
      return;
    }
    final label = _openLabel.toString();
    _openUri = null;
    _openLabel.clear();
    if (label.isEmpty) {
      return;
    }
    _spans.add(_HyperlinkSpan(label: label, uri: uri));
    if (_spans.length > _maxSpans) {
      _spans.removeRange(0, _spans.length - _maxSpans);
    }
  }

  String _safeDecode(Uint8List bytes) {
    try {
      return utf8.decode(bytes, allowMalformed: true);
    } on FormatException {
      return String.fromCharCodes(bytes);
    }
  }
}

class _HyperlinkSpan {
  _HyperlinkSpan({required this.label, required this.uri});

  final String label;
  final String uri;
}

class _LineSegment {
  _LineSegment({required this.row, required this.start, required this.length});

  final int row;
  final int start;
  final int length;
}

enum _OscState { text, escape, oscBody, oscStPending, csiBody }
