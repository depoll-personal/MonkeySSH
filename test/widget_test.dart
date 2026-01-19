// ignore_for_file: public_member_api_docs

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutty/app/app.dart';

void main() {
  testWidgets('App renders home screen', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: FluttyApp()));
    await tester.pumpAndSettle();

    expect(find.text('Flutty'), findsOneWidget);
    expect(find.text('Quick Connect'), findsOneWidget);
    expect(find.text('Hosts'), findsOneWidget);
    expect(find.text('Keys'), findsOneWidget);
    expect(find.text('Snippets'), findsOneWidget);
  });

  testWidgets('Navigation cards are tappable', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: FluttyApp()));
    await tester.pumpAndSettle();

    // Find and tap the Hosts card
    final hostsCard = find.text('Hosts');
    expect(hostsCard, findsOneWidget);
    await tester.tap(hostsCard);
    await tester.pumpAndSettle();

    // For now, just verify no crash - navigation will be added later
  });
}
