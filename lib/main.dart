import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ghostty_vte_flutter/ghostty_vte_flutter.dart';

import 'app/app.dart';
import 'app/host_key_prompt.dart';
import 'domain/services/host_key_prompt_handler_provider.dart';

/// Entry point for the MonkeySSH client.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) {
    await initializeGhosttyVteWeb();
  }
  runApp(
    ProviderScope(
      overrides: [
        hostKeyPromptHandlerProvider.overrideWith(
          (ref) => createHostKeyPromptHandler(),
        ),
      ],
      child: const FluttyApp(),
    ),
  );
}
