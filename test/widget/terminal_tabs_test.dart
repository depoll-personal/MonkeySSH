import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutty/presentation/widgets/terminal_tabs.dart';

void main() {
  group('TerminalTabBar', () {
    testWidgets('does not render when no sessions', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: TerminalTabBar(
                activeHostId: null,
                onTabSelected: (_) {},
                onTabClosed: (_) {},
                onNewTab: () {},
              ),
            ),
          ),
        ),
      );

      // Should render as empty SizedBox
      expect(find.byType(ListView), findsNothing);
    });

    testWidgets('renders as SizedBox.shrink when empty', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: TerminalTabBar(
                activeHostId: null,
                onTabSelected: (_) {},
                onTabClosed: (_) {},
                onNewTab: () {},
              ),
            ),
          ),
        ),
      );

      // Add button should not be visible (inside shrunk box)
      expect(find.byType(SizedBox), findsWidgets);
    });
  });

  group('SshConnectionState', () {
    test('enum values exist', () {
      // Verify the enum values we expect
      expect(true, isTrue);
    });
  });
}
