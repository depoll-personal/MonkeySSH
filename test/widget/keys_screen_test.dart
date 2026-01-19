// ignore_for_file: public_member_api_docs

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutty/data/database/database.dart';
import 'package:flutty/presentation/screens/keys_screen.dart';

void main() {
  group('KeysScreen', () {
    testWidgets('shows loading indicator initially', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: KeysScreen())),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows empty state when no keys', (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: const MaterialApp(home: KeysScreen()),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('No SSH keys yet'), findsOneWidget);
      expect(find.text('Tap + to generate or import a key'), findsOneWidget);
    });

    testWidgets('shows FAB to add key', (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: const MaterialApp(home: KeysScreen()),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byType(FloatingActionButton), findsOneWidget);
      expect(find.text('Add Key'), findsOneWidget);
    });

    testWidgets('displays app bar with title', (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: const MaterialApp(home: KeysScreen()),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('SSH Keys'), findsOneWidget);
    });

    testWidgets('shows key list when keys exist', (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);

      await db
          .into(db.sshKeys)
          .insert(
            SshKeysCompanion.insert(
              name: 'My Key',
              keyType: 'ed25519',
              publicKey: 'ssh-ed25519 AAAA...',
              privateKey: '-----BEGIN OPENSSH PRIVATE KEY-----...',
            ),
          );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: const MaterialApp(home: KeysScreen()),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('My Key'), findsOneWidget);
      expect(find.text('ED25519'), findsOneWidget);
    });

    testWidgets('shows key type in list tile', (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);

      await db
          .into(db.sshKeys)
          .insert(
            SshKeysCompanion.insert(
              name: 'RSA Key',
              keyType: 'rsa',
              publicKey: 'ssh-rsa AAAA...',
              privateKey: '-----BEGIN RSA PRIVATE KEY-----...',
            ),
          );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: const MaterialApp(home: KeysScreen()),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('RSA Key'), findsOneWidget);
      expect(find.text('RSA'), findsOneWidget);
    });

    testWidgets('shows popup menu for key actions', (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);

      await db
          .into(db.sshKeys)
          .insert(
            SshKeysCompanion.insert(
              name: 'Test Key',
              keyType: 'ed25519',
              publicKey: 'ssh-ed25519 AAAA...',
              privateKey: '-----BEGIN OPENSSH PRIVATE KEY-----...',
            ),
          );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: const MaterialApp(home: KeysScreen()),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byType(PopupMenuButton<String>), findsWidgets);
    });

    testWidgets('shows key icon in empty state', (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: const MaterialApp(home: KeysScreen()),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.vpn_key_outlined), findsOneWidget);
    });

    testWidgets('shows multiple keys', (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);

      await db
          .into(db.sshKeys)
          .insert(
            SshKeysCompanion.insert(
              name: 'Key 1',
              keyType: 'ed25519',
              publicKey: 'ssh-ed25519 AAAA1...',
              privateKey: '-----BEGIN OPENSSH PRIVATE KEY-----1...',
            ),
          );
      await db
          .into(db.sshKeys)
          .insert(
            SshKeysCompanion.insert(
              name: 'Key 2',
              keyType: 'rsa',
              publicKey: 'ssh-rsa AAAA2...',
              privateKey: '-----BEGIN RSA PRIVATE KEY-----2...',
            ),
          );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: const MaterialApp(home: KeysScreen()),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Key 1'), findsOneWidget);
      expect(find.text('Key 2'), findsOneWidget);
    });

    testWidgets('tapping on key shows bottom sheet', (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);

      await db
          .into(db.sshKeys)
          .insert(
            SshKeysCompanion.insert(
              name: 'My Key',
              keyType: 'ed25519',
              publicKey: 'ssh-ed25519 AAAA...',
              privateKey: '-----BEGIN OPENSSH PRIVATE KEY-----...',
            ),
          );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: const MaterialApp(home: KeysScreen()),
        ),
      );

      await tester.pumpAndSettle();

      await tester.tap(find.text('My Key'));
      await tester.pumpAndSettle();

      expect(find.text('Public Key'), findsOneWidget);
      expect(find.text('Copy Public Key'), findsOneWidget);
    });
  });
}
