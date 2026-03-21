// ignore_for_file: public_member_api_docs

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:monkeyssh/domain/models/ai_cli_provider.dart';
import 'package:monkeyssh/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('imports a key and completes a live AI chat flow', (
    tester,
  ) async {
    if (!_isLiveUxConfigured) {
      debugPrint(
        'Skipping live UX validation. Provide FLUTTY_LIVE_UX_PORT, '
        'FLUTTY_LIVE_UX_USERNAME, FLUTTY_LIVE_UX_PRIVATE_KEY_BASE64, and '
        'FLUTTY_LIVE_UX_WORKSPACE_PATH.',
      );
      return;
    }

    final runId = DateTime.now().millisecondsSinceEpoch;
    final keyName = 'UX Key $runId';
    final hostLabel = 'UX Host $runId';

    app.main();
    await tester.pumpAndSettle();
    await _skipAuthSetupIfPresent(tester);

    await _tapNavigationDestination(tester, 'nav-keys');
    await _pumpUntilVisible(
      tester,
      find.byKey(const Key('home-keys-add-button')),
    );
    await tester.tap(find.byKey(const Key('home-keys-add-button')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Import'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), keyName);
    await tester.enterText(find.byType(TextFormField).at(1), _privateKeyPem);
    await tester.tap(find.byKey(const Key('import-key-primary-action')));
    await tester.pump();
    await _pumpUntilVisible(
      tester,
      find.text(keyName),
      timeout: const Duration(seconds: 20),
    );

    await _tapNavigationDestination(tester, 'nav-hosts');
    await _pumpUntilVisible(
      tester,
      find.byKey(const Key('home-hosts-add-button')),
    );
    await tester.tap(find.byKey(const Key('home-hosts-add-button')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), hostLabel);
    await tester.enterText(find.byType(TextFormField).at(1), _liveUxHost);
    await tester.enterText(find.byType(TextFormField).at(2), '$_liveUxPort');
    await tester.enterText(find.byType(TextFormField).at(3), _liveUxUsername);

    await _scrollUntilVisible(
      tester,
      find.byKey(const Key('host-ssh-key-field')),
    );
    await tester.tap(find.byKey(const Key('host-ssh-key-field')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(keyName).last);
    await tester.pumpAndSettle();

    await _scrollUntilVisible(
      tester,
      find.byKey(const Key('host-save-button')),
    );
    await tester.tap(find.byKey(const Key('host-save-button')));
    await tester.pump();
    await _pumpUntilVisible(
      tester,
      find.text(hostLabel),
      timeout: const Duration(seconds: 20),
    );

    await _tapNavigationDestination(tester, 'nav-ai-chat');
    await _pumpUntilVisible(tester, _findHostDropdown());

    await tester.tap(_findHostDropdown());
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining(hostLabel).last);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('ai-working-directory-field')),
      _liveUxWorkspacePath,
    );
    await tester.tap(_findProviderDropdown());
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(Key('ai-provider-option-${_liveUxProvider.name}')).last,
    );
    await tester.pumpAndSettle();
    await _configureAcpClientIfNeeded(tester);

    await tester.tap(find.text('Start Session'));
    await tester.pump();
    await _pumpUntilVisible(
      tester,
      find.byKey(const Key('ai-chat-input')),
      timeout: const Duration(seconds: 60),
    );
    await tester.enterText(find.byKey(const Key('ai-chat-input')), '/help');
    await _pumpUntilButtonEnabled(
      tester,
      find.byKey(const Key('ai-chat-send-button')),
    );
    await tester.tap(find.byKey(const Key('ai-chat-send-button')));
    await tester.pump();
    await _pumpUntilVisible(
      tester,
      find.bySemanticsLabel(RegExp(r'Assistant\n')),
      timeout: const Duration(seconds: 30),
    );

    await tester.enterText(
      find.byKey(const Key('ai-chat-input')),
      'Reply with the uppercase version of monkeyssh and nothing else.',
    );
    await _pumpUntilButtonEnabled(
      tester,
      find.byKey(const Key('ai-chat-send-button')),
    );
    await tester.tap(find.byKey(const Key('ai-chat-send-button')));
    await tester.pump();
    await _pumpUntilVisible(
      tester,
      find.bySemanticsLabel(RegExp('MONKEYSSH')),
      timeout: const Duration(minutes: 1),
    );

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    await _tapNavigationDestination(tester, 'nav-ai-chat');
    await _pumpUntilVisible(
      tester,
      find.byKey(const Key('ai-recent-sessions-card')),
      timeout: const Duration(seconds: 20),
    );

    final recentSessionTile = find.descendant(
      of: find.byKey(const Key('ai-recent-sessions-card')),
      matching: find.byType(ListTile),
    );
    await _pumpUntilVisible(
      tester,
      recentSessionTile,
      timeout: const Duration(seconds: 20),
    );
    await _scrollUntilVisible(tester, recentSessionTile.first);
    await tester.tap(recentSessionTile.first, warnIfMissed: false);
    await tester.pumpAndSettle();
    await _pumpUntilVisible(
      tester,
      find.byKey(const Key('ai-chat-input')),
      timeout: const Duration(seconds: 20),
    );
    await _pumpUntilVisible(
      tester,
      find.bySemanticsLabel(RegExp('MONKEYSSH')),
      timeout: const Duration(seconds: 20),
    );
  });
}

Finder _findProviderDropdown() => find.byWidgetPredicate(
  (widget) => widget is DropdownButtonFormField<AiCliProvider>,
  description: 'AI provider dropdown',
);

Finder _findHostDropdown() => find.byWidgetPredicate(
  (widget) => widget is DropdownButtonFormField<int>,
  description: 'Host dropdown',
);

const _liveUxPort = int.fromEnvironment('FLUTTY_LIVE_UX_PORT');
const _liveUxUsername = String.fromEnvironment('FLUTTY_LIVE_UX_USERNAME');
const _liveUxHostFromDefine = String.fromEnvironment('FLUTTY_LIVE_UX_HOST');
const _liveUxProviderRaw = String.fromEnvironment(
  'FLUTTY_LIVE_UX_PROVIDER',
  defaultValue: 'copilot',
);
const _liveUxAcpClientId = String.fromEnvironment(
  'FLUTTY_LIVE_UX_ACP_CLIENT_ID',
);
const _liveUxAcpClientCommand = String.fromEnvironment(
  'FLUTTY_LIVE_UX_ACP_CLIENT_COMMAND',
);
const _liveUxPrivateKeyBase64 = String.fromEnvironment(
  'FLUTTY_LIVE_UX_PRIVATE_KEY_BASE64',
);
const _liveUxWorkspacePath = String.fromEnvironment(
  'FLUTTY_LIVE_UX_WORKSPACE_PATH',
);

bool get _isLiveUxConfigured =>
    _liveUxPort > 0 &&
    _liveUxUsername.isNotEmpty &&
    _liveUxPrivateKeyBase64.isNotEmpty &&
    _liveUxWorkspacePath.isNotEmpty &&
    _resolvedLiveUxProvider != null &&
    (_resolvedLiveUxProvider != AiCliProvider.acp ||
        _liveUxAcpClientId.isNotEmpty ||
        _liveUxAcpClientCommand.isNotEmpty);

AiCliProvider get _liveUxProvider => _resolvedLiveUxProvider!;

AiCliProvider? get _resolvedLiveUxProvider {
  for (final provider in AiCliProvider.values) {
    if (provider.name == _liveUxProviderRaw) {
      return provider;
    }
  }
  return null;
}

String get _liveUxHost => _liveUxHostFromDefine.isNotEmpty
    ? _liveUxHostFromDefine
    : Platform.isAndroid
    ? '10.0.2.2'
    : '127.0.0.1';

String get _privateKeyPem => utf8.decode(base64Decode(_liveUxPrivateKeyBase64));

const _acpPresetLabelsById = <String, String>{
  'opencode': 'OpenCode',
  'copilot': 'GitHub Copilot',
  'gemini': 'Gemini CLI',
  'generic-stdio': 'Generic ACP Client (stdio)',
};

Future<void> _skipAuthSetupIfPresent(WidgetTester tester) async {
  final skipButton = find.text('Skip');
  if (skipButton.evaluate().isEmpty) {
    return;
  }
  await tester.tap(skipButton);
  await tester.pumpAndSettle();
}

Future<void> _configureAcpClientIfNeeded(WidgetTester tester) async {
  if (_liveUxProvider != AiCliProvider.acp) {
    return;
  }

  await _pumpUntilVisible(
    tester,
    find.byKey(const Key('ai-acp-client-preset-field')),
  );
  await tester.tap(find.byKey(const Key('ai-acp-client-preset-field')));
  await tester.pumpAndSettle();

  if (_liveUxAcpClientCommand.isNotEmpty) {
    await tester.tap(find.text('Custom command').last);
    await tester.pumpAndSettle();
    await _pumpUntilVisible(
      tester,
      find.byKey(const Key('ai-acp-client-command-field')),
    );
    await tester.enterText(
      find.byKey(const Key('ai-acp-client-command-field')),
      _liveUxAcpClientCommand,
    );
    await tester.pumpAndSettle();
    return;
  }

  final presetLabel = _acpPresetLabelsById[_liveUxAcpClientId];
  if (presetLabel == null) {
    fail('Unknown ACP preset id: $_liveUxAcpClientId');
  }
  await tester.tap(find.text(presetLabel).last);
  await tester.pumpAndSettle();
}

Future<void> _tapNavigationDestination(
  WidgetTester tester,
  String keyValue,
) async {
  await _pumpUntilVisible(tester, find.byKey(Key(keyValue)));
  await tester.tap(find.byKey(Key(keyValue)));
  await tester.pumpAndSettle();
}

Future<void> _scrollUntilVisible(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpUntilVisible(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 250));
    if (finder.evaluate().isNotEmpty) {
      return;
    }
  }
  expect(finder, findsWidgets);
}

Future<void> _pumpUntilButtonEnabled(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 250));
    final elements = finder.evaluate().toList(growable: false);
    if (elements.isEmpty) {
      continue;
    }
    final widget = elements.first.widget;
    if (widget case final FilledButton button when button.onPressed != null) {
      return;
    }
  }
  final widget = tester.widget<FilledButton>(finder);
  expect(widget.onPressed, isNotNull);
}
