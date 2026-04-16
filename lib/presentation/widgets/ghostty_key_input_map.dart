import 'package:flutter/services.dart';
import 'package:ghostty_vte_flutter/ghostty_vte_flutter.dart';

/// Mapping of Flutter logical keyboard keys to Ghostty terminal keys.
///
/// Wraps the upstream [ghosttyTerminalLogicalKeyMap] with the extra keys the
/// Flutty keyboard toolbar surfaces (Ctrl, Shift, Alt, Meta, Escape, Tab,
/// space, etc.) so call sites can obtain a `GhosttyKey` from a
/// [LogicalKeyboardKey] without repeatedly consulting the upstream table.
GhosttyKey? logicalKeyToGhosttyKey(LogicalKeyboardKey key) {
  final mapped = ghosttyTerminalLogicalKey(key);
  if (mapped != null) {
    return mapped;
  }
  return _extraKeyMap[key];
}

final Map<LogicalKeyboardKey, GhosttyKey> _extraKeyMap =
    <LogicalKeyboardKey, GhosttyKey>{
      LogicalKeyboardKey.space: GhosttyKey.GHOSTTY_KEY_SPACE,
      LogicalKeyboardKey.capsLock: GhosttyKey.GHOSTTY_KEY_CAPS_LOCK,
      LogicalKeyboardKey.scrollLock: GhosttyKey.GHOSTTY_KEY_SCROLL_LOCK,
      LogicalKeyboardKey.numLock: GhosttyKey.GHOSTTY_KEY_NUM_LOCK,
      LogicalKeyboardKey.printScreen: GhosttyKey.GHOSTTY_KEY_PRINT_SCREEN,
      LogicalKeyboardKey.pause: GhosttyKey.GHOSTTY_KEY_PAUSE,
      LogicalKeyboardKey.shiftLeft: GhosttyKey.GHOSTTY_KEY_SHIFT_LEFT,
      LogicalKeyboardKey.shiftRight: GhosttyKey.GHOSTTY_KEY_SHIFT_RIGHT,
      LogicalKeyboardKey.controlLeft: GhosttyKey.GHOSTTY_KEY_CONTROL_LEFT,
      LogicalKeyboardKey.controlRight: GhosttyKey.GHOSTTY_KEY_CONTROL_RIGHT,
      LogicalKeyboardKey.altLeft: GhosttyKey.GHOSTTY_KEY_ALT_LEFT,
      LogicalKeyboardKey.altRight: GhosttyKey.GHOSTTY_KEY_ALT_RIGHT,
      LogicalKeyboardKey.metaLeft: GhosttyKey.GHOSTTY_KEY_META_LEFT,
      LogicalKeyboardKey.metaRight: GhosttyKey.GHOSTTY_KEY_META_RIGHT,
    };

/// Computes a Ghostty modifier mask from the current modifier flags.
int ghosttyModifierMask({
  bool shift = false,
  bool control = false,
  bool alt = false,
  bool meta = false,
}) {
  var mods = 0;
  if (shift) {
    mods |= GhosttyModsMask.shift;
  }
  if (control) {
    mods |= GhosttyModsMask.ctrl;
  }
  if (alt) {
    mods |= GhosttyModsMask.alt;
  }
  if (meta) {
    mods |= GhosttyModsMask.superKey;
  }
  return mods;
}
