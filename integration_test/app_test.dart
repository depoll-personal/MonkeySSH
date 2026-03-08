import 'dart:convert';

import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:monkeyssh/data/database/database.dart';
import 'package:monkeyssh/data/repositories/host_repository.dart';
import 'package:monkeyssh/data/repositories/key_repository.dart';
import 'package:monkeyssh/data/security/secret_encryption_service.dart';
import 'package:monkeyssh/domain/services/auth_service.dart';
import 'package:monkeyssh/domain/services/key_service.dart';
import 'package:monkeyssh/main.dart' as app;
import 'package:monkeyssh/presentation/screens/home_screen.dart';
import 'package:monkeyssh/presentation/screens/hosts_screen.dart';
import 'package:xterm/xterm.dart';

const _testSshEnabled = bool.fromEnvironment('TEST_SSH_ENABLED');
const _testSshHost = String.fromEnvironment(
  'TEST_SSH_HOST',
  defaultValue: '127.0.0.1',
);
const _testSshPort = int.fromEnvironment('TEST_SSH_PORT', defaultValue: 22);
const _testSshUsername = String.fromEnvironment('TEST_SSH_USERNAME');
const _testSshPrivateKeyBase64 = String.fromEnvironment(
  'TEST_SSH_PRIVATE_KEY_B64',
);
const _seededHostLabel = 'Local SSH Target';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('App Integration Tests', () {
    testWidgets('home screen loads and shows navigation options', (
      tester,
    ) async {
      app.main();
      await _pumpUntilVisible(tester, find.text('MonkeySSH'));

      expect(find.text('MonkeySSH'), findsOneWidget);
      expect(find.text('Hosts'), findsOneWidget);
      expect(find.text('Connections'), findsOneWidget);
      expect(find.text('Keys'), findsOneWidget);
      expect(find.text('Snippets'), findsOneWidget);
    });

    testWidgets('settings exposes the security setup flow', (tester) async {
      app.main();
      await _pumpUntilVisible(tester, find.byIcon(Icons.settings_outlined));

      await tester.tap(find.byIcon(Icons.settings_outlined));
      await _pumpUntilVisible(tester, find.text('Settings'));

      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Set up app lock'), findsOneWidget);

      await tester.tap(find.text('Set up app lock'));
      await _pumpUntilVisible(tester, find.text('Security Setup'));

      expect(find.text('Security Setup'), findsOneWidget);
      expect(find.text('Skip for now'), findsOneWidget);
    });

    testWidgets('hosts search waits for apply before dismissing', (
      tester,
    ) async {
      app.main();
      await _pumpUntilVisible(tester, find.text('MonkeySSH'));

      final context = tester.element(find.byType(HomeScreen));
      GoRouter.of(context).go('/hosts');
      await _pumpUntilVisible(tester, find.byType(HostsScreen));

      await tester.tap(find.byTooltip('Search'));
      await _pumpUntilVisible(tester, find.text('Search Hosts'));

      expect(find.text('Search Hosts'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'prod');
      await tester.pump();
      expect(find.text('Search Hosts'), findsOneWidget);

      await tester.tap(find.text('Apply'));
      await _pumpUntilVisible(tester, find.text('Search: prod'));

      expect(find.text('No hosts match your search'), findsOneWidget);
      expect(find.text('Search: prod'), findsOneWidget);
      expect(find.text('Clear all'), findsOneWidget);
    });

    testWidgets('can connect to a seeded SSH host', (tester) async {
      await _seedSshHost();

      app.main();
      await _pumpUntilVisible(tester, find.text(_seededHostLabel));

      expect(find.text(_seededHostLabel), findsOneWidget);

      await tester.tap(find.text(_seededHostLabel));
      await tester.pump();
      await _pumpUntilTerminalReady(tester);

      await tester.tap(find.byType(PopupMenuButton<String>));
      await _pumpUntilVisible(tester, find.text('Disconnect'));
      expect(find.text('Disconnect'), findsOneWidget);
    }, skip: !_testSshEnabled);
  });
}

Future<void> _seedSshHost() async {
  final privateKeyPem = _decodeTestPrivateKey();
  final authService = AuthService();
  await authService.disableAuth();

  final db = AppDatabase();
  final secretEncryptionService = SecretEncryptionService();
  final keyRepository = KeyRepository(db, secretEncryptionService);
  final hostRepository = HostRepository(db, secretEncryptionService);
  final keyService = KeyService(keyRepository);

  try {
    await db.delete(db.portForwards).go();
    await db.delete(db.hosts).go();
    await db.delete(db.sshKeys).go();

    final importedKey = await keyService.importKey(
      name: 'Integration SSH Key',
      privateKeyPem: privateKeyPem,
    );
    if (importedKey == null) {
      throw StateError('Failed to import integration SSH key');
    }

    await hostRepository.insert(
      HostsCompanion.insert(
        label: _seededHostLabel,
        hostname: _testSshHost,
        port: const drift.Value(_testSshPort),
        username: _testSshUsername,
        keyId: drift.Value(importedKey.id),
      ),
    );
  } finally {
    await db.close();
  }
}

String _decodeTestPrivateKey() {
  if (!_testSshEnabled ||
      _testSshUsername.isEmpty ||
      _testSshPrivateKeyBase64.isEmpty) {
    throw StateError('Missing SSH integration test configuration');
  }

  return utf8.decode(base64Decode(_testSshPrivateKeyBase64));
}

Future<void> _pumpUntilVisible(
  WidgetTester tester,
  Finder finder, {
  Duration step = const Duration(milliseconds: 200),
  int maxTicks = 50,
}) async {
  for (var i = 0; i < maxTicks; i++) {
    await tester.pump(step);
    if (finder.evaluate().isNotEmpty) {
      return;
    }
  }

  fail('Timed out waiting for expected widget to appear');
}

Future<void> _pumpUntilTerminalReady(WidgetTester tester) async {
  final terminalView = find.byType(TerminalView);
  final connectionError = find.text('Connection Error');

  for (var i = 0; i < 75; i++) {
    await tester.pump(const Duration(milliseconds: 200));
    if (connectionError.evaluate().isNotEmpty) {
      fail('SSH integration test hit a connection error');
    }
    if (terminalView.evaluate().isNotEmpty) {
      return;
    }
  }

  fail('Timed out waiting for terminal connection to finish');
}
