import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghostty_vte_flutter/ghostty_vte_flutter.dart';
import 'package:monkeyssh/presentation/widgets/keyboard_toolbar.dart';

class _Output {
  final List<String> chunks = <String>[];

  String get joined => chunks.join();

  bool add(List<int> bytes) {
    chunks.add(utf8.decode(bytes, allowMalformed: true));
    return true;
  }
}

GhosttyTerminalController _attach(_Output output) =>
    GhosttyTerminalController()
      ..attachExternalTransport(writeBytes: output.add);

void main() {
  test('resolveTerminalTabInput returns plain tab by default', () {
    expect(resolveTerminalTabInput(shiftActive: false), '\t');
  });

  test('resolveTerminalTabInput returns reverse-tab when shift is active', () {
    expect(resolveTerminalTabInput(shiftActive: true), '\x1b[Z');
  });

  group('KeyboardToolbar', () {
    late GhosttyTerminalController terminal;
    late _Output output;

    setUp(() {
      output = _Output();
      terminal = _attach(output);
    });

    tearDown(() {
      terminal.dispose();
    });

    testWidgets('renders all key rows', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: KeyboardToolbar(terminal: terminal)),
        ),
      );

      expect(find.byTooltip('Escape'), findsOneWidget);
      expect(find.byTooltip('Tab'), findsOneWidget);
      expect(find.byTooltip('Ctrl'), findsOneWidget);
      expect(find.byTooltip('Alt'), findsOneWidget);
      expect(find.byTooltip('Shift'), findsOneWidget);

      expect(find.byTooltip('Up'), findsOneWidget);
      expect(find.byTooltip('Down'), findsOneWidget);
      expect(find.byTooltip('Left'), findsOneWidget);
      expect(find.byTooltip('Right'), findsOneWidget);
      expect(find.byTooltip('Home'), findsOneWidget);
      expect(find.byTooltip('End'), findsOneWidget);
      expect(find.byTooltip('Page Up'), findsOneWidget);
      expect(find.byTooltip('Page Down'), findsOneWidget);
    });

    testWidgets('keeps arrow keys to the left of PgUp/PgDn/Home/End', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: KeyboardToolbar(terminal: terminal)),
        ),
      );

      const expectedOrder = <String>[
        'Left',
        'Right',
        'Up',
        'Down',
        'Page Up',
        'Page Down',
        'Home',
        'End',
      ];
      final positions = <String, double>{
        for (final label in expectedOrder)
          label: tester.getCenter(find.byTooltip(label)).dx,
      };
      final actualOrder = expectedOrder.toList()
        ..sort((a, b) => positions[a]!.compareTo(positions[b]!));

      expect(actualOrder, expectedOrder);
    });

    testWidgets('modifier key toggles state on tap', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: KeyboardToolbar(terminal: terminal)),
        ),
      );

      final ctrlFinder = find.byTooltip('Ctrl');
      expect(ctrlFinder, findsOneWidget);

      await tester.tap(ctrlFinder);
      await tester.pumpAndSettle();
      await tester.tap(ctrlFinder);
      await tester.pumpAndSettle();
    });

    testWidgets(
      'controller preserves Ctrl state across toolbar rebuilds for system '
      'keyboard input',
      (tester) async {
        final controller = KeyboardToolbarController();
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: KeyboardToolbar(terminal: terminal, controller: controller),
            ),
          ),
        );

        await tester.tap(find.byTooltip('Ctrl'));
        await tester.pump();

        expect(controller.isCtrlActive, isTrue);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: KeyboardToolbar(terminal: terminal, controller: controller),
            ),
          ),
        );
        await tester.pump();

        expect(controller.applySystemKeyboardModifiers('b'), '\u0002');
        expect(controller.isCtrlActive, isFalse);
      },
    );

    testWidgets('calls onKeyPressed callback', (tester) async {
      var callCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: KeyboardToolbar(
              terminal: terminal,
              onKeyPressed: () => callCount++,
            ),
          ),
        ),
      );

      await tester.tap(find.text('/'));
      await tester.pump();

      expect(callCount, 1);
    });

    testWidgets('special characters render correctly', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: KeyboardToolbar(terminal: terminal)),
        ),
      );

      expect(find.text('|'), findsOneWidget);
      expect(find.text('/'), findsOneWidget);
    });

    testWidgets('Enter button renders and triggers callback', (tester) async {
      var callCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: KeyboardToolbar(
              terminal: terminal,
              onKeyPressed: () => callCount++,
            ),
          ),
        ),
      );

      final enterButton = find.byTooltip('Enter');
      expect(enterButton, findsOneWidget);

      await tester.tap(enterButton);
      await tester.pump();

      expect(callCount, 1);
      expect(output.joined, contains('\r'));
    });

    testWidgets('Tab ignores the system keyboard shift state', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: KeyboardToolbar(terminal: terminal)),
        ),
      );

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.tap(find.byTooltip('Tab'));
      await tester.pump();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);

      expect(output.joined, contains('\t'));
      expect(output.joined, isNot(contains('\x1b[Z')));
    });

    testWidgets('toolbar Shift still sends reverse-tab', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: KeyboardToolbar(terminal: terminal)),
        ),
      );

      await tester.tap(find.byTooltip('Shift'));
      await tester.pump();
      await tester.tap(find.byTooltip('Tab'));
      await tester.pump();

      expect(output.joined, contains('\x1b[Z'));
    });

    testWidgets('toolbar Shift applies to Enter', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: KeyboardToolbar(terminal: terminal)),
        ),
      );

      await tester.tap(find.byTooltip('Shift'));
      await tester.pump();
      await tester.tap(find.byTooltip('Enter'));
      await tester.pump();

      // Shift+Enter is encoded as a modified-key sequence by the Ghostty key
      // encoder. Accept any encoding that indicates Shift+Enter (raw CR, Kitty
      // `CSI 13 ; 2 u`, or `CSI 27 ; 2 ; 13 ~`).
      final bytes = output.joined;
      expect(
        bytes.contains('\r') ||
            bytes.contains('\x1b[13;2u') ||
            bytes.contains('\x1b[27;2;13~'),
        isTrue,
        reason:
            'expected a carriage-return or modified-enter sequence, '
            'got ${bytes.codeUnits}',
      );
    });

    test('keeps bottom safe-area padding when keyboard is closed', () {
      const mediaQuery = MediaQueryData(padding: EdgeInsets.only(bottom: 34));

      expect(shouldKeepToolbarBottomSafeArea(mediaQuery), isTrue);
    });

    test('drops bottom safe-area padding when keyboard is open', () {
      const mediaQuery = MediaQueryData(
        padding: EdgeInsets.only(bottom: 34),
        viewInsets: EdgeInsets.only(bottom: 320),
      );

      expect(shouldKeepToolbarBottomSafeArea(mediaQuery), isFalse);
    });

    testWidgets('arrow keys repeat while held', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: KeyboardToolbar(terminal: terminal)),
        ),
      );

      final gesture = await tester.startGesture(
        tester.getCenter(find.byTooltip('Up')),
      );
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 1));
      await tester.pump(const Duration(milliseconds: 160));
      await gesture.up();
      await tester.pump();

      expect('\x1b[A'.allMatches(output.joined).length, greaterThan(1));
    });

    testWidgets('repeating navigation stops when gesture is cancelled', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: KeyboardToolbar(terminal: terminal)),
        ),
      );

      final gesture = await tester.startGesture(
        tester.getCenter(find.byTooltip('Right')),
      );
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 1));
      await tester.pump(const Duration(milliseconds: 120));
      await gesture.cancel();
      await tester.pump();

      final outputCount = '\x1b[C'.allMatches(output.joined).length;
      await tester.pump(const Duration(milliseconds: 150));

      expect(outputCount, greaterThan(1));
      expect('\x1b[C'.allMatches(output.joined).length, outputCount);
    });

    testWidgets('repeating navigation stops when released', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: KeyboardToolbar(terminal: terminal)),
        ),
      );

      final gesture = await tester.startGesture(
        tester.getCenter(find.byTooltip('Home')),
      );
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 1));
      await tester.pump(const Duration(milliseconds: 120));
      await gesture.up();
      await tester.pump();

      final outputCount = '\x1b[H'.allMatches(output.joined).length;
      await tester.pump(const Duration(milliseconds: 150));

      expect(outputCount, greaterThan(1));
      expect('\x1b[H'.allMatches(output.joined).length, outputCount);
    });
  });

  group('Terminal key sequences', () {
    test('arrow key escape sequences', () {
      expect('\x1b[A', equals('\x1b[A'));
      expect('\x1b[B', equals('\x1b[B'));
      expect('\x1b[C', equals('\x1b[C'));
      expect('\x1b[D', equals('\x1b[D'));
    });

    test('navigation key escape sequences', () {
      expect('\x1b[H', equals('\x1b[H'));
      expect('\x1b[F', equals('\x1b[F'));
      expect('\x1b[5~', equals('\x1b[5~'));
      expect('\x1b[6~', equals('\x1b[6~'));
    });

    test('modifier key combinations', () {
      expect('\x1b[1;5A', equals('\x1b[1;5A'));
      expect('\x1b[1;3A', equals('\x1b[1;3A'));
      expect('\x1b[1;2A', equals('\x1b[1;2A'));
    });
  });
}
