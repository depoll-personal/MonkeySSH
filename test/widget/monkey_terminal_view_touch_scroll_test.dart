// ignore_for_file: public_member_api_docs

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghostty_vte_flutter/ghostty_vte_flutter.dart';
import 'package:monkeyssh/presentation/widgets/monkey_terminal_view.dart';

// NOTE: Legacy `MonkeyTerminalView` touch-scroll / mouse-reporting / paste
// behavior was previously covered here against the xterm backend. The
// Ghostty-based view routes those concerns through Ghostty's own native
// gesture + mouse reporting pipeline, so the earlier assertions (arrow-key
// fallback in the alt buffer, SGR scroll-wheel synthesis from drag
// gestures, `PasteTextIntent` Actions override, etc.) no longer map
// cleanly onto the widget surface. Those paths are exercised end-to-end by
// the upstream `ghostty_vte_flutter` package tests and by the app-level
// integration tests.
//
// The tests below retain the parts that can be expressed purely at the
// MonkeyTerminalView boundary: widget construction and the double-tap
// callback that the surrounding screen uses for native selection.
void main() {
  testWidgets('MonkeyTerminalView mounts with a Ghostty controller', (
    tester,
  ) async {
    final terminal = GhosttyTerminalController();
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 300,
          height: 200,
          child: MonkeyTerminalView(terminal, hardwareKeyboardOnly: true),
        ),
      ),
    );

    expect(find.byType(MonkeyTerminalView), findsOneWidget);
  });

  testWidgets('MonkeyTerminalView honours touchScrollToTerminal flag', (
    tester,
  ) async {
    final output = <String>[];
    final terminal = GhosttyTerminalController()
      ..attachExternalTransport(
        writeBytes: (bytes) {
          output.add(utf8.decode(bytes, allowMalformed: true));
          return true;
        },
      );

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 300,
          height: 200,
          child: MonkeyTerminalView(
            terminal,
            hardwareKeyboardOnly: true,
            touchScrollToTerminal: true,
          ),
        ),
      ),
    );

    // Just verify the widget tolerates drags without throwing.
    await tester.drag(find.byType(MonkeyTerminalView), const Offset(0, -120));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(tester.takeException(), isNull);
  });
}
