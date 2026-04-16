import 'package:flutter/foundation.dart';

/// Row/column offset into the terminal transcript.
///
/// Mirrors the simple (x, y) shape of `xterm`'s CellOffset so call sites in
/// the terminal screen and related widgets can continue to express locations
/// as `(column, row)` after the Ghostty migration.
@immutable
class CellOffset {
  /// Creates a new [CellOffset] with the given [x] (column) and [y] (row).
  const CellOffset(this.x, this.y);

  /// Zero-based column index within the transcript line.
  final int x;

  /// Zero-based row index within the transcript (0 == topmost retained line).
  final int y;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CellOffset &&
          runtimeType == other.runtimeType &&
          x == other.x &&
          y == other.y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => 'CellOffset($x, $y)';
}
