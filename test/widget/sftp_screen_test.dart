import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monkeyssh/presentation/screens/sftp_screen.dart';

void main() {
  group('measureMaxLineWidth', () {
    test('returns zero for empty text', () {
      expect(
        measureMaxLineWidth(
          text: '',
          style: const TextStyle(),
          textDirection: TextDirection.ltr,
          textScaler: TextScaler.noScaling,
        ),
        0,
      );
    });

    test('returns width of the widest line plus slack', () {
      final width = measureMaxLineWidth(
        text: 'short\na somewhat longer line\nhi',
        style: const TextStyle(),
        textDirection: TextDirection.ltr,
        textScaler: TextScaler.noScaling,
      );
      // Should be > 0 and include trailing slack.
      expect(width, greaterThan(0));
    });
  });

  group('measureCaretX', () {
    test('returns zero at offset zero', () {
      expect(
        measureCaretX(
          text: 'hello',
          offset: 0,
          style: const TextStyle(),
          textDirection: TextDirection.ltr,
          textScaler: TextScaler.noScaling,
        ),
        0,
      );
    });

    test('returns zero for negative offset', () {
      expect(
        measureCaretX(
          text: 'hello',
          offset: -5,
          style: const TextStyle(),
          textDirection: TextDirection.ltr,
          textScaler: TextScaler.noScaling,
        ),
        0,
      );
    });

    test('returns non-zero for mid-line offset', () {
      expect(
        measureCaretX(
          text: 'hello world',
          offset: 5,
          style: const TextStyle(),
          textDirection: TextDirection.ltr,
          textScaler: TextScaler.noScaling,
        ),
        greaterThan(0),
      );
    });

    test('resets at start of a new line', () {
      expect(
        measureCaretX(
          text: 'hello\nworld',
          offset: 6,
          style: const TextStyle(),
          textDirection: TextDirection.ltr,
          textScaler: TextScaler.noScaling,
        ),
        0,
      );
    });
  });

  group('Remote text editor widget', () {
    testWidgets(
      'nowrap viewport stays fixed while scrolling selection into view',
      (tester) async {
        final longLine = List<String>.filled(80, '0123456789').join();
        final controller = TextEditingController(text: longLine)
          ..selection = TextSelection.collapsed(offset: longLine.length);
        final horizontalScrollController = ScrollController();

        addTearDown(() async {
          await tester.binding.setSurfaceSize(null);
          horizontalScrollController.dispose();
          controller.dispose();
        });

        await tester.binding.setSurfaceSize(const Size(420, 720));
        await tester.pumpWidget(
          MaterialApp(
            home: buildRemoteTextEditorScreenForTesting(
              fileName: 'notes.txt',
              controller: controller,
              horizontalScrollController: horizontalScrollController,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          tester
              .getSize(
                find.byKey(
                  const ValueKey<String>('remoteTextEditorNowrapViewport'),
                ),
              )
              .width,
          greaterThan(300),
        );
        expect(horizontalScrollController.offset, greaterThan(0));
      },
    );

    testWidgets('caret-following works from offset zero', (tester) async {
      final longLine = List<String>.filled(80, '0123456789').join();
      final controller = TextEditingController(text: longLine)
        ..selection = const TextSelection.collapsed(offset: 0);
      final horizontalScrollController = ScrollController();

      addTearDown(() async {
        await tester.binding.setSurfaceSize(null);
        horizontalScrollController.dispose();
        controller.dispose();
      });

      await tester.binding.setSurfaceSize(const Size(420, 720));
      await tester.pumpWidget(
        MaterialApp(
          home: buildRemoteTextEditorScreenForTesting(
            fileName: 'notes.txt',
            controller: controller,
            horizontalScrollController: horizontalScrollController,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(horizontalScrollController.offset, 0);

      controller.selection = TextSelection.collapsed(offset: longLine.length);
      await tester.pumpAndSettle();
      expect(horizontalScrollController.offset, greaterThan(0));
    });

    testWidgets('works after bottom sheet dismissal', (tester) async {
      final longLine = List<String>.filled(80, '0123456789').join();
      final controller = TextEditingController(text: longLine)
        ..selection = TextSelection.collapsed(offset: longLine.length);
      final horizontalScrollController = ScrollController();

      addTearDown(() async {
        await tester.binding.setSurfaceSize(null);
        horizontalScrollController.dispose();
        controller.dispose();
      });

      await tester.binding.setSurfaceSize(const Size(420, 720));
      await tester.pumpWidget(
        MaterialApp(
          home: _BottomSheetEditorLauncher(
            controller: controller,
            horizontalScrollController: horizontalScrollController,
          ),
        ),
      );

      await tester.tap(find.text('Open editor'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();

      expect(find.text('Edit notes.txt'), findsOneWidget);
      expect(horizontalScrollController.offset, greaterThan(0));
    });

    testWidgets('opens without error with no explicit selection', (
      tester,
    ) async {
      final controller = TextEditingController(
        text: List<String>.filled(80, '0123456789').join(),
      );
      final horizontalScrollController = ScrollController();

      addTearDown(() async {
        await tester.binding.setSurfaceSize(null);
        horizontalScrollController.dispose();
        controller.dispose();
      });

      await tester.binding.setSurfaceSize(const Size(420, 720));
      await tester.pumpWidget(
        MaterialApp(
          home: buildRemoteTextEditorScreenForTesting(
            fileName: 'notes.txt',
            controller: controller,
            horizontalScrollController: horizontalScrollController,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Edit notes.txt'), findsOneWidget);
    });

    testWidgets('anchors at left edge with invalid initial selection', (
      tester,
    ) async {
      final controller = TextEditingController(
        text: List<String>.filled(80, '0123456789').join(),
      );
      final horizontalScrollController = ScrollController();

      addTearDown(() async {
        await tester.binding.setSurfaceSize(null);
        horizontalScrollController.dispose();
        controller.dispose();
      });

      await tester.binding.setSurfaceSize(const Size(420, 720));
      await tester.pumpWidget(
        MaterialApp(
          home: buildRemoteTextEditorScreenForTesting(
            fileName: 'notes.txt',
            controller: controller,
            horizontalScrollController: horizontalScrollController,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(controller.selection, const TextSelection.collapsed(offset: 0));
      expect(horizontalScrollController.offset, 0);
    });

    testWidgets('shows cursor position in status bar', (tester) async {
      final controller = TextEditingController(text: 'hello\nworld\nfoo')
        ..selection = const TextSelection.collapsed(offset: 8);
      final horizontalScrollController = ScrollController();

      addTearDown(() async {
        await tester.binding.setSurfaceSize(null);
        horizontalScrollController.dispose();
        controller.dispose();
      });

      await tester.binding.setSurfaceSize(const Size(420, 720));
      await tester.pumpWidget(
        MaterialApp(
          home: buildRemoteTextEditorScreenForTesting(
            fileName: 'notes.txt',
            controller: controller,
            horizontalScrollController: horizontalScrollController,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Offset 8 = 'hello\nwo' → line 2, column 3
      expect(find.text('Ln 2, Col 3'), findsOneWidget);
    });

    testWidgets('status bar updates when cursor moves', (tester) async {
      final controller = TextEditingController(text: 'hello\nworld\nfoo')
        ..selection = const TextSelection.collapsed(offset: 0);
      final horizontalScrollController = ScrollController();

      addTearDown(() async {
        await tester.binding.setSurfaceSize(null);
        horizontalScrollController.dispose();
        controller.dispose();
      });

      await tester.binding.setSurfaceSize(const Size(420, 720));
      await tester.pumpWidget(
        MaterialApp(
          home: buildRemoteTextEditorScreenForTesting(
            fileName: 'notes.txt',
            controller: controller,
            horizontalScrollController: horizontalScrollController,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Ln 1, Col 1'), findsOneWidget);

      // Move cursor to line 3, col 4 (offset 15 = 'hello\nworld\nfoo')
      controller.selection = const TextSelection.collapsed(offset: 15);
      await tester.pumpAndSettle();
      expect(find.text('Ln 3, Col 4'), findsOneWidget);
    });
  });
}

class _BottomSheetEditorLauncher extends StatelessWidget {
  const _BottomSheetEditorLauncher({
    required this.controller,
    required this.horizontalScrollController,
  });

  final TextEditingController controller;
  final ScrollController horizontalScrollController;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: ElevatedButton(
        onPressed: () {
          showModalBottomSheet<void>(
            context: context,
            builder: (sheetContext) => SafeArea(
              child: ListTile(
                title: const Text('Edit'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      fullscreenDialog: true,
                      builder: (context) =>
                          buildRemoteTextEditorScreenForTesting(
                            fileName: 'notes.txt',
                            controller: controller,
                            horizontalScrollController:
                                horizontalScrollController,
                          ),
                    ),
                  );
                },
              ),
            ),
          );
        },
        child: const Text('Open editor'),
      ),
    ),
  );
}
