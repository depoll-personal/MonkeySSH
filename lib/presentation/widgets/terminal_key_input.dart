import 'package:ghostty_vte_flutter/ghostty_vte_flutter.dart';

import 'ghostty_key_input_map.dart';

/// Sends Enter with the active terminal modifiers applied.
void sendTerminalEnterInput(
  GhosttyTerminalController controller, {
  required bool shiftActive,
  required bool altActive,
  required bool ctrlActive,
}) {
  controller.sendKey(
    key: GhosttyKey.GHOSTTY_KEY_ENTER,
    mods: ghosttyModifierMask(
      shift: shiftActive,
      alt: altActive,
      control: ctrlActive,
    ),
  );
}
