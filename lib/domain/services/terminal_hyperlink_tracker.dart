import 'package:flutter/foundation.dart';
import 'package:ghostty_vte_flutter/ghostty_vte_flutter.dart';

import '../models/cell_offset.dart';

/// Tracks OSC 8 terminal hyperlinks so taps can open links whose labels do not
/// visibly contain the destination URL.
///
/// Under the Ghostty VTE backend, the controller's
/// [GhosttyTerminalSnapshot] preserves cell-level hyperlink metadata via
/// [GhosttyTerminalSnapshot.hyperlinkAt]. This tracker simply forwards
/// resolve requests to the snapshot — OSC 8 sequences do not need to be
/// intercepted separately because Ghostty parses and retains them natively.
class TerminalHyperlinkTracker {
  GhosttyTerminalController? _controller;

  /// Attaches this tracker to [controller].
  ///
  /// Reattaching to the same controller is a no-op.
  void attach(GhosttyTerminalController controller) {
    if (identical(_controller, controller)) {
      return;
    }
    _controller = controller;
  }

  /// Clears the controller reference.
  void reset({bool keepControllerReference = true}) {
    if (!keepControllerReference) {
      _controller = null;
    }
  }

  /// Handles a private OSC sequence.
  ///
  /// Retained for API compatibility — Ghostty's VTE already parses OSC 8
  /// internally, so this is a no-op. Remaining callers that still funnel
  /// OSC sequences through the tracker continue to work unchanged.
  void handlePrivateOsc(String code, List<String> args) {
    // OSC 8 is handled natively by the Ghostty terminal.
  }

  /// Resolves the hyperlink at [offset], if the cell at that row/column is
  /// linked by an active OSC 8 hyperlink.
  String? resolveLinkAt(CellOffset offset) {
    final controller = _controller;
    if (controller == null) {
      return null;
    }
    final snapshot = controller.snapshot;
    return snapshot.hyperlinkAt(
      GhosttyTerminalCellPosition(row: offset.y, col: offset.x),
    );
  }

  /// Number of fully tracked hyperlinks currently retained in memory.
  ///
  /// Ghostty tracks hyperlinks inside its own snapshot, so this value is
  /// reported as zero; retained for test-only access compatibility.
  @visibleForTesting
  int get trackedHyperlinkCount => 0;
}
