import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:monkeyssh/app/app.dart';
import 'package:monkeyssh/data/database/database.dart';
import 'package:monkeyssh/data/repositories/host_repository.dart';
import 'package:monkeyssh/data/repositories/key_repository.dart';
import 'package:monkeyssh/data/repositories/snippet_repository.dart';
import 'package:monkeyssh/data/security/secret_encryption_service.dart';
import 'package:monkeyssh/domain/services/auth_service.dart';
import 'package:monkeyssh/domain/services/key_service.dart';
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
const _qaPublicKey =
    'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIClipboardQaKey qa@device';
const _qaPrivateKey =
    '-----BEGIN OPENSSH PRIVATE KEY-----\nqa-private-key\n-----END OPENSSH PRIVATE KEY-----';
const _qaSnippetCommand = 'echo "qa clipboard snippet"';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('App Integration Tests', () {
    testWidgets('home screen loads and shows navigation options', (
      tester,
    ) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      await AuthService().disableAuth();
      await _launchApp(tester, db);
      await _pumpUntilVisible(tester, find.text('MonkeySSH'));

      expect(find.text('MonkeySSH'), findsOneWidget);
      expect(find.text('Hosts'), findsWidgets);
      expect(find.text('Connections'), findsOneWidget);
      expect(find.text('Keys'), findsOneWidget);
      expect(find.text('Snippets'), findsOneWidget);
    });

    testWidgets('settings exposes the security setup flow', (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      await AuthService().disableAuth();
      await _launchApp(tester, db);
      await _pumpUntilVisible(tester, find.byIcon(Icons.settings_outlined));

      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pump();
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
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      await AuthService().disableAuth();
      await _launchApp(tester, db);
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

    testWidgets('keys screen copies public and private keys to clipboard', (
      tester,
    ) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      await AuthService().disableAuth();
      await _seedClipboardKey(db);

      await _launchApp(tester, db);
      await _pumpUntilVisible(tester, find.text('MonkeySSH'));

      final context = tester.element(find.byType(HomeScreen));
      GoRouter.of(context).go('/keys');
      await _pumpUntilVisible(tester, find.text('QA Clipboard Key'));

      await tester.tap(find.text('QA Clipboard Key'));
      await _pumpUntilVisible(tester, find.text('Copy Public Key'));

      await tester.tap(find.text('Copy Public Key'));
      await _pumpUntilVisible(tester, find.text('Copied to clipboard'));
      expect(
        (await Clipboard.getData(Clipboard.kTextPlain))?.text,
        _qaPublicKey,
      );

      await tester.tap(find.text('Reveal Private Key'));
      await _pumpUntilVisible(tester, find.text('Copy Private Key'));
      await tester.tap(find.text('Copy Private Key'));
      await _pumpUntilVisible(tester, find.text('Copy private key?'));
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(FilledButton, 'Copy'),
        ),
      );
      await _pumpUntilVisible(tester, find.text('Copied to clipboard'));
      expect(
        (await Clipboard.getData(Clipboard.kTextPlain))?.text,
        _qaPrivateKey,
      );
    });

    testWidgets('snippets list scrolls and copies commands to clipboard', (
      tester,
    ) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      await AuthService().disableAuth();
      await _seedClipboardSnippets(db);

      await _launchApp(tester, db);
      await _pumpUntilVisible(tester, find.text('MonkeySSH'));

      final context = tester.element(find.byType(HomeScreen));
      GoRouter.of(context).go('/snippets');
      await _pumpUntilVisible(tester, find.text('QA Snippet 00'));

      await tester.drag(find.byType(ListView).first, const Offset(0, -900));
      await tester.pumpAndSettle();
      await _pumpUntilVisible(tester, find.text('QA Snippet 11'));

      await tester.tap(find.text('QA Snippet 11'));
      await _pumpUntilVisible(
        tester,
        find.text('Copied "QA Snippet 11" to clipboard'),
      );
      expect(
        (await Clipboard.getData(Clipboard.kTextPlain))?.text,
        'printf "snippet-11"',
      );
    });

    testWidgets('terminal connection error can navigate back to hosts', (
      tester,
    ) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      await AuthService().disableAuth();
      final hostId = await _seedInvalidHost(db);

      await _launchApp(tester, db);
      await _pumpUntilVisible(tester, find.text('MonkeySSH'));

      final context = tester.element(find.byType(HomeScreen));
      unawaited(GoRouter.of(context).push('/terminal/$hostId'));
      await _pumpUntilVisible(tester, find.text('Connection Error'));

      expect(find.text('Back to Hosts'), findsOneWidget);
      await tester.tap(find.widgetWithText(OutlinedButton, 'Back to Hosts'));
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(OutlinedButton, 'Back to Hosts'),
        findsNothing,
      );
      expect(find.text('Connection Error'), findsNothing);
    });

    testWidgets('can connect to a seeded SSH host', (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      await AuthService().disableAuth();
      await _seedSshHost(db);

      await _launchApp(tester, db);
      await _pumpUntilVisible(tester, find.text(_seededHostLabel));

      expect(find.text(_seededHostLabel), findsOneWidget);

      await tester.tap(find.text(_seededHostLabel));
      await tester.pump();
      await _pumpUntilTerminalReady(tester);

      expect(find.byType(TerminalView), findsOneWidget);
      expect(find.text(_seededHostLabel), findsWidgets);
    }, skip: !_testSshEnabled);
  });
}

Future<void> _launchApp(WidgetTester tester, AppDatabase db) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
      child: const FluttyApp(),
    ),
  );
  await tester.pump();
}

Future<void> _seedClipboardKey(AppDatabase db) async {
  final secretEncryptionService = SecretEncryptionService();
  final keyRepository = KeyRepository(db, secretEncryptionService);

  await db.delete(db.sshKeys).go();

  await keyRepository.insert(
    SshKeysCompanion.insert(
      name: 'QA Clipboard Key',
      keyType: 'ed25519',
      publicKey: _qaPublicKey,
      privateKey: _qaPrivateKey,
    ),
  );
}

Future<void> _seedClipboardSnippets(AppDatabase db) async {
  final snippetRepository = SnippetRepository(db);

  await db.delete(db.snippets).go();

  for (var index = 0; index < 12; index++) {
    final number = index.toString().padLeft(2, '0');
    await snippetRepository.insert(
      SnippetsCompanion.insert(
        name: 'QA Snippet $number',
        command: index == 11 ? 'printf "snippet-11"' : _qaSnippetCommand,
      ),
    );
  }
}

Future<int> _seedInvalidHost(AppDatabase db) async {
  final secretEncryptionService = SecretEncryptionService();
  final hostRepository = HostRepository(db, secretEncryptionService);

  await db.delete(db.portForwards).go();
  await db.delete(db.hosts).go();

  return hostRepository.insert(
    HostsCompanion.insert(
      label: 'Broken QA Host',
      hostname: '127.0.0.1',
      port: const drift.Value(1),
      username: 'qa',
    ),
  );
}

Future<void> _seedSshHost(AppDatabase db) async {
  final privateKeyPem = _decodeTestPrivateKey();
  final secretEncryptionService = SecretEncryptionService();
  final keyRepository = KeyRepository(db, secretEncryptionService);
  final hostRepository = HostRepository(db, secretEncryptionService);
  final keyService = KeyService(keyRepository);

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
      hostname: _runtimeSshHost(),
      port: const drift.Value(_testSshPort),
      username: _testSshUsername,
      keyId: drift.Value(importedKey.id),
    ),
  );
}

String _decodeTestPrivateKey() {
  if (!_testSshEnabled ||
      _testSshUsername.isEmpty ||
      _testSshPrivateKeyBase64.isEmpty) {
    throw StateError('Missing SSH integration test configuration');
  }

  return utf8.decode(base64Decode(_testSshPrivateKeyBase64));
}

String _runtimeSshHost() {
  if (Platform.isAndroid && _testSshHost == '127.0.0.1') {
    return '10.0.2.2';
  }

  return _testSshHost;
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
