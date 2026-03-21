import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:monkeyssh/presentation/screens/key_add_screen.dart';

void main() {
  group('KeyAddScreen', () {
    testWidgets('keeps import actions visible on narrow screens', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 520);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: KeyAddScreen())),
      );

      await tester.tap(find.text('Import'));
      await tester.pumpAndSettle();

      final importKeyButton = find.byKey(
        const Key('import-key-primary-action'),
      );
      final importFileButton = find.byKey(const Key('import-key-file-action'));

      expect(importKeyButton.hitTestable(), findsOneWidget);
      expect(importFileButton.hitTestable(), findsOneWidget);

      final importKeyRect = tester.getRect(importKeyButton);
      final importFileRect = tester.getRect(importFileButton);

      expect(importKeyRect.bottom, lessThanOrEqualTo(520));
      expect(importFileRect.bottom, lessThanOrEqualTo(520));
    });
  });
}
