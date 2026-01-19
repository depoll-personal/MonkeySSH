// ignore_for_file: public_member_api_docs

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutty/data/database/database.dart';
import 'package:flutty/presentation/screens/snippets_screen.dart';

void main() {
  group('SnippetsScreen', () {
    testWidgets('shows loading indicator initially', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: SnippetsScreen())),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows empty state when no snippets', (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: const MaterialApp(home: SnippetsScreen()),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('No snippets yet'), findsOneWidget);
      expect(find.text('Tap + to create a snippet'), findsOneWidget);
    });

    testWidgets('shows FAB to add snippet', (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: const MaterialApp(home: SnippetsScreen()),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byType(FloatingActionButton), findsOneWidget);
      expect(find.text('Add Snippet'), findsOneWidget);
    });

    testWidgets('shows folders button in app bar', (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: const MaterialApp(home: SnippetsScreen()),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.folder), findsOneWidget);
    });

    testWidgets('displays app bar with title', (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: const MaterialApp(home: SnippetsScreen()),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Snippets'), findsOneWidget);
    });

    testWidgets('shows snippet list when snippets exist', (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);

      // Insert test snippets
      await db
          .into(db.snippets)
          .insert(
            SnippetsCompanion.insert(name: 'List Files', command: 'ls -la'),
          );
      await db
          .into(db.snippets)
          .insert(
            SnippetsCompanion.insert(name: 'Disk Usage', command: 'df -h'),
          );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: const MaterialApp(home: SnippetsScreen()),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('List Files'), findsOneWidget);
      expect(find.text('Disk Usage'), findsOneWidget);
    });

    testWidgets('shows snippet command in list tile', (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);

      await db
          .into(db.snippets)
          .insert(
            SnippetsCompanion.insert(name: 'List Files', command: 'ls -la'),
          );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: const MaterialApp(home: SnippetsScreen()),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('ls -la'), findsOneWidget);
    });

    testWidgets('shows popup menu for snippet actions', (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);

      await db
          .into(db.snippets)
          .insert(SnippetsCompanion.insert(name: 'Test', command: 'test'));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: const MaterialApp(home: SnippetsScreen()),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byType(PopupMenuButton<String>), findsWidgets);
    });

    testWidgets('shows code icon in empty state', (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: const MaterialApp(home: SnippetsScreen()),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.code_outlined), findsOneWidget);
    });

    testWidgets('tapping folders button shows snackbar', (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: const MaterialApp(home: SnippetsScreen()),
        ),
      );

      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.folder));
      await tester.pumpAndSettle();

      expect(find.text('Folders coming soon'), findsOneWidget);
    });
  });
}
