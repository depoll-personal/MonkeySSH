// ignore_for_file: public_member_api_docs

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monkeyssh/data/database/database.dart';
import 'package:monkeyssh/data/repositories/ai_repository.dart';
import 'package:monkeyssh/data/repositories/key_repository.dart';
import 'package:monkeyssh/data/security/secret_encryption_service.dart';
import 'package:monkeyssh/domain/models/ai_cli_provider.dart';
import 'package:monkeyssh/domain/services/ai_cli_launch_arguments_builder.dart';
import 'package:monkeyssh/domain/services/ai_cli_session_preferences.dart';
import 'package:monkeyssh/domain/services/ai_runtime_event_parser_pipeline.dart';
import 'package:monkeyssh/domain/services/ai_runtime_service.dart';
import 'package:monkeyssh/domain/services/ssh_service.dart';

void main() {
  final skipReason = _realCopilotTestSkipReason();

  test(
    'runs Copilot slash help over SSH and resumes the provider session',
    () async {
      final workspacePath = Directory.current.path;
      final sshd = await _DisposableSshd.start();
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          secretEncryptionServiceProvider.overrideWithValue(
            SecretEncryptionService.forTesting(),
          ),
        ],
      );

      addTearDown(() async {
        await container.read(activeSessionsProvider.notifier).disconnectAll();
        container.dispose();
        await db.close();
        await sshd.dispose();
      });

      final keyId = await container
          .read(keyRepositoryProvider)
          .insert(
            SshKeysCompanion.insert(
              name: 'Integration key',
              keyType: 'ed25519',
              publicKey: sshd.clientPublicKey,
              privateKey: sshd.clientPrivateKey,
            ),
          );
      final hostId = await db
          .into(db.hosts)
          .insert(
            HostsCompanion.insert(
              label: 'Local Copilot',
              hostname: '127.0.0.1',
              username: sshd.username,
              port: Value(sshd.port),
              keyId: Value(keyId),
            ),
          );
      final workspaceId = await db
          .into(db.aiWorkspaces)
          .insert(
            AiWorkspacesCompanion.insert(
              name: 'Integration workspace',
              path: workspacePath,
            ),
          );
      final sessionId = await db
          .into(db.aiSessions)
          .insert(
            AiSessionsCompanion.insert(
              workspaceId: workspaceId,
              title: 'Copilot SSH integration',
            ),
          );

      final connectionResult = await _withStepTimeout(
        'SSH connect',
        container.read(activeSessionsProvider.notifier).connect(hostId),
        sshd: sshd,
      );
      expect(connectionResult.success, isTrue);
      final connectionId = connectionResult.connectionId;
      expect(connectionId, isNotNull);

      final runtimeService = container.read(aiRuntimeServiceProvider);
      final parser = container.read(aiRuntimeEventParserPipelineProvider);
      final repository = container.read(aiRepositoryProvider);
      const launchArgumentsBuilder = AiCliLaunchArgumentsBuilder();
      final parsedEvents = <AiTimelineEvent>[];
      final rawRuntimeEvents = <String>[];
      final parsedEventSubscription = parser.bind(runtimeService.events).listen(
        (event) {
          if (event.aiSessionId == sessionId) {
            parsedEvents.add(event);
          }
        },
      );
      final rawEventSubscription = runtimeService.events.listen((event) {
        if (event.aiSessionId != sessionId) {
          return;
        }
        final chunk = event.chunk;
        rawRuntimeEvents.add(
          '${event.type.name}${chunk == null ? '' : ': ${_compact(chunk)}'}',
        );
      });
      addTearDown(parsedEventSubscription.cancel);
      addTearDown(rawEventSubscription.cancel);

      Future<List<AiTimelineEvent>> runHelp({String? providerSessionId}) async {
        parsedEvents.clear();
        rawRuntimeEvents.clear();
        final request = AiRuntimeLaunchRequest(
          aiSessionId: sessionId,
          connectionId: connectionId!,
          provider: AiCliProvider.copilot,
          executableOverride: _copilotExecutable,
          remoteWorkingDirectory: workspacePath,
          structuredOutput: true,
          extraArguments: launchArgumentsBuilder.buildHeadlessPromptArguments(
            provider: AiCliProvider.copilot,
            preferences: AiCliSessionPreferences(
              providerSessionId: providerSessionId,
            ),
            prompt: '/help',
          ),
          runInPtyOverride: false,
        );
        await _withStepTimeout(
          'Copilot launch',
          runtimeService.launch(request),
          sshd: sshd,
          rawRuntimeEvents: rawRuntimeEvents,
          parsedEvents: parsedEvents,
        );
        await _waitForParsedCondition(
          'Copilot /help output',
          () =>
              _providerSessionIdFrom(parsedEvents) != null &&
              parsedEvents.any(
                (event) =>
                    event.type == AiTimelineEventType.status &&
                    event.message.contains('Copilot turn completed'),
              ),
          sshd: sshd,
          rawRuntimeEvents: rawRuntimeEvents,
          parsedEvents: parsedEvents,
        );
        if (runtimeService.hasActiveRunForSession(sessionId)) {
          await _withStepTimeout(
            'Copilot teardown',
            runtimeService.cancel(aiSessionId: sessionId),
            sshd: sshd,
            rawRuntimeEvents: rawRuntimeEvents,
            parsedEvents: parsedEvents,
          );
        }
        await Future<void>.delayed(const Duration(milliseconds: 500));
        for (final event in parsedEvents) {
          await repository.insertTimelineEntry(
            AiTimelineEntriesCompanion.insert(
              sessionId: sessionId,
              role: _timelineRole(event.type),
              message: event.message,
              metadata: Value(
                jsonEncode(<String, dynamic>{
                  'provider': event.provider.name,
                  ...event.metadata,
                }),
              ),
            ),
          );
        }
        return List<AiTimelineEvent>.from(parsedEvents);
      }

      final firstRunEvents = await runHelp();
      final firstProviderSessionId = _providerSessionIdFrom(firstRunEvents);

      expect(firstProviderSessionId, isNotNull);
      expect(
        firstRunEvents.any(
          (event) =>
              event.type == AiTimelineEventType.tool &&
              event.metadata['toolName'] == 'fetch_copilot_cli_documentation',
        ),
        isTrue,
      );
      final persistedEntriesAfterFirstRun = await (db.select(
        db.aiTimelineEntries,
      )..where((entry) => entry.sessionId.equals(sessionId))).get();
      expect(
        persistedEntriesAfterFirstRun.any(
          (entry) =>
              entry.metadata?.contains(
                '"providerSessionId":"$firstProviderSessionId"',
              ) ??
              false,
        ),
        isTrue,
      );

      final secondRunEvents = await runHelp(
        providerSessionId: firstProviderSessionId,
      );
      final secondProviderSessionId = _providerSessionIdFrom(secondRunEvents);

      expect(secondProviderSessionId, firstProviderSessionId);
      expect(
        secondRunEvents.any(
          (event) =>
              event.type == AiTimelineEventType.status &&
              event.message.contains('Copilot turn completed'),
        ),
        isTrue,
      );
    },
    skip: skipReason,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

const _copilotExecutable = '/Users/depoll/homebrew/bin/copilot';

String? _realCopilotTestSkipReason() {
  if (!Platform.isMacOS) {
    return 'Requires macOS-local sshd and Copilot CLI.';
  }
  if (!File(_copilotExecutable).existsSync()) {
    return 'Copilot CLI is not installed at $_copilotExecutable.';
  }
  if (Platform.environment['FLUTTY_RUN_REAL_AI_CLI_TESTS'] != '1') {
    return 'Set FLUTTY_RUN_REAL_AI_CLI_TESTS=1 to run real SSH/Copilot tests.';
  }
  return null;
}

Future<T> _withStepTimeout<T>(
  String description,
  Future<T> future, {
  required _DisposableSshd sshd,
  List<String>? rawRuntimeEvents,
  List<AiTimelineEvent>? parsedEvents,
}) async {
  try {
    return await future.timeout(const Duration(seconds: 20));
  } on TimeoutException {
    throw StateError(
      '$description timed out.\n'
      'SSH log:\n${await sshd.readLog()}\n'
      'Raw runtime events:\n${_formatLines(rawRuntimeEvents)}\n'
      'Parsed events:\n${_formatParsedEvents(parsedEvents)}',
    );
  } on Exception catch (error) {
    throw StateError(
      '$description failed: $error\n'
      'SSH log:\n${await sshd.readLog()}\n'
      'Raw runtime events:\n${_formatLines(rawRuntimeEvents)}\n'
      'Parsed events:\n${_formatParsedEvents(parsedEvents)}',
    );
  }
}

Future<void> _waitForParsedCondition(
  String description,
  bool Function() condition, {
  required _DisposableSshd sshd,
  List<String>? rawRuntimeEvents,
  List<AiTimelineEvent>? parsedEvents,
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 45));
  while (DateTime.now().isBefore(deadline)) {
    if (condition()) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  throw StateError(
    '$description timed out.\n'
    'SSH log:\n${await sshd.readLog()}\n'
    'Raw runtime events:\n${_formatLines(rawRuntimeEvents)}\n'
    'Parsed events:\n${_formatParsedEvents(parsedEvents)}',
  );
}

String _formatLines(List<String>? values) {
  if (values == null || values.isEmpty) {
    return '(none)';
  }
  return values.join('\n');
}

String _formatParsedEvents(List<AiTimelineEvent>? events) {
  if (events == null || events.isEmpty) {
    return '(none)';
  }
  return events
      .map(
        (event) =>
            '${event.type.name}: ${_compact(event.message)} '
            '${event.metadata.isEmpty ? '' : event.metadata}',
      )
      .join('\n');
}

String _compact(String value) => value
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim()
    .substring(
      0,
      value.replaceAll(RegExp(r'\s+'), ' ').trim().length.clamp(0, 240),
    );

String? _providerSessionIdFrom(List<AiTimelineEvent> events) {
  for (final event in events.reversed) {
    final providerSessionId = event.metadata['providerSessionId']?.toString();
    if (providerSessionId != null && providerSessionId.trim().isNotEmpty) {
      return providerSessionId;
    }
  }
  return null;
}

String _timelineRole(AiTimelineEventType type) => switch (type) {
  AiTimelineEventType.message => 'assistant',
  AiTimelineEventType.tool => 'tool',
  AiTimelineEventType.thinking => 'thinking',
  AiTimelineEventType.status => 'status',
  AiTimelineEventType.error => 'error',
};

class _DisposableSshd {
  _DisposableSshd({
    required this.tempDir,
    required this.process,
    required this.port,
    required this.username,
    required this.clientKeyPath,
    required this.clientPrivateKey,
    required this.clientPublicKey,
  });

  final Directory tempDir;
  final Process process;
  final int port;
  final String username;
  final String clientKeyPath;
  final String clientPrivateKey;
  final String clientPublicKey;

  static Future<_DisposableSshd> start() async {
    final tempDir = await Directory.systemTemp.createTemp('monkeyssh-ai-ssh-');
    final usernameResult = await Process.run('/usr/bin/id', <String>['-un']);
    final username = usernameResult.stdout.toString().trim();
    if (usernameResult.exitCode != 0 || username.isEmpty) {
      throw StateError(
        'Unable to resolve the current username for SSH tests: ${usernameResult.stderr}',
      );
    }

    final clientKeyPath = '${tempDir.path}/id_ed25519';
    final hostKeyPath = '${tempDir.path}/ssh_host_ed25519_key';
    final authorizedKeysPath = '${tempDir.path}/authorized_keys';
    final configPath = '${tempDir.path}/sshd_config';
    final logPath = '${tempDir.path}/sshd.log';
    final port = 42240 + DateTime.now().millisecond % 1000;

    Future<void> generateKey(String path) async {
      final result = await Process.run('/usr/bin/ssh-keygen', <String>[
        '-q',
        '-t',
        'ed25519',
        '-N',
        '',
        '-f',
        path,
      ]);
      if (result.exitCode != 0) {
        throw StateError('ssh-keygen failed for $path: ${result.stderr}');
      }
    }

    await generateKey(clientKeyPath);
    await generateKey(hostKeyPath);

    final publicKey = await File('$clientKeyPath.pub').readAsString();
    await File(authorizedKeysPath).writeAsString(publicKey);
    await File(configPath).writeAsString('''
Port $port
ListenAddress 127.0.0.1
HostKey $hostKeyPath
PidFile ${tempDir.path}/sshd.pid
AuthorizedKeysFile $authorizedKeysPath
PasswordAuthentication no
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
PubkeyAuthentication yes
PermitRootLogin no
UsePAM no
AllowUsers $username
PrintMotd no
PermitTTY yes
StrictModes no
LogLevel ERROR
Subsystem sftp internal-sftp
''');

    final process = await Process.start('/usr/sbin/sshd', <String>[
      '-D',
      '-f',
      configPath,
      '-E',
      logPath,
    ]);

    final disposable = _DisposableSshd(
      tempDir: tempDir,
      process: process,
      port: port,
      username: username,
      clientKeyPath: clientKeyPath,
      clientPrivateKey: await File(clientKeyPath).readAsString(),
      clientPublicKey: publicKey,
    );
    await disposable._waitUntilReady();
    return disposable;
  }

  Future<void> _waitUntilReady() async {
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (DateTime.now().isBefore(deadline)) {
      try {
        final result = await Process.run('/usr/bin/ssh', <String>[
          '-o',
          'BatchMode=yes',
          '-o',
          'StrictHostKeyChecking=no',
          '-o',
          'UserKnownHostsFile=/dev/null',
          '-o',
          'IdentitiesOnly=yes',
          '-i',
          clientKeyPath,
          '-p',
          '$port',
          '$username@127.0.0.1',
          '/usr/bin/true',
        ]);
        if (result.exitCode == 0) {
          return;
        }
      } on ProcessException {
        // Keep polling until pubkey auth succeeds.
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    throw StateError(
      'Timed out waiting for test sshd to start.\n${await readLog()}',
    );
  }

  Future<String> readLog() async {
    final logFile = File('${tempDir.path}/sshd.log');
    if (!logFile.existsSync()) {
      return '(missing)';
    }
    return logFile.readAsString();
  }

  Future<void> dispose() async {
    process.kill();
    await process.exitCode.timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        process.kill(ProcessSignal.sigkill);
        return -1;
      },
    );
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  }
}
