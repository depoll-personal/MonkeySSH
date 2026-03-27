import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monkeyssh/presentation/screens/sftp_screen.dart';

void main() {
  group('currentLinePrefixAtTextOffset', () {
    test('returns the current line prefix for a multiline selection', () {
      expect(currentLinePrefixAtTextOffset('alpha\nbeta\ngamma', 10), 'beta');
    });

    test('returns empty string at offset zero', () {
      expect(currentLinePrefixAtTextOffset('hello', 0), '');
    });

    test('returns empty string for negative offset', () {
      expect(currentLinePrefixAtTextOffset('hello', -1), '');
    });
  });

  group('resolveUnwrappedEditorSelectionScrollOffset', () {
    test('scrolls right when the caret moves beyond the viewport', () {
      expect(
        resolveUnwrappedEditorSelectionScrollOffset(
          text: '0123456789',
          selection: const TextSelection.collapsed(offset: 10),
          style: const TextStyle(),
          textDirection: TextDirection.ltr,
          textScaler: TextScaler.noScaling,
          viewportWidth: 40,
          trailingSlack: 5,
          measureLineWidth: (line, _) => (line.length * 10).toDouble(),
        ),
        65,
      );
    });

    test('scrolls left when the caret moves before the viewport', () {
      expect(
        resolveUnwrappedEditorSelectionScrollOffset(
          text: '0123456789',
          selection: const TextSelection.collapsed(offset: 2),
          style: const TextStyle(),
          textDirection: TextDirection.ltr,
          textScaler: TextScaler.noScaling,
          viewportWidth: 40,
          currentOffset: 70,
          trailingSlack: 5,
          measureLineWidth: (line, _) => (line.length * 10).toDouble(),
        ),
        15,
      );
    });

    test('returns currentOffset when selection offset is zero', () {
      expect(
        resolveUnwrappedEditorSelectionScrollOffset(
          text: '0123456789',
          selection: const TextSelection.collapsed(offset: 0),
          style: const TextStyle(),
          textDirection: TextDirection.ltr,
          textScaler: TextScaler.noScaling,
          viewportWidth: 40,
          trailingSlack: 5,
          measureLineWidth: (line, _) => (line.length * 10).toDouble(),
        ),
        0,
      );
    });
  });

  group('buildRemoteTextEditorScreenForTesting', () {
    testWidgets(
      'keeps the nowrap viewport fixed while scrolling the selection into view',
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
          closeTo(372, 0.1),
        );
        expect(horizontalScrollController.offset, greaterThan(0));
      },
    );

    testWidgets('caret-following works when selection starts at offset zero', (
      tester,
    ) async {
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

      // Offset 0 — no horizontal scroll needed yet.
      expect(horizontalScrollController.offset, 0);

      // Move cursor to end; caret-following should scroll.
      controller.selection = TextSelection.collapsed(offset: longLine.length);
      await tester.pumpAndSettle();
      expect(horizontalScrollController.offset, greaterThan(0));
    });

    testWidgets(
      'keeps long nowrap text visible when opened after a bottom sheet closes',
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
      },
    );

    testWidgets(
      'opens without error when controller has no explicit selection',
      (tester) async {
        // Real app flow: TextEditingController(text: content) without setting
        // selection — default is TextSelection.collapsed(offset: -1).
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

        // Should render without errors.
        expect(find.text('Edit notes.txt'), findsOneWidget);
      },
    );

    testWidgets(
      'keeps invalid initial selection anchored at the left edge on open',
      (tester) async {
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
      },
    );
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
