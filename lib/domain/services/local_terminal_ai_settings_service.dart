import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'local_terminal_ai_managed_model_service.dart';
import 'settings_service.dart';

/// Persisted settings for the experimental on-device terminal AI assistant.
class LocalTerminalAiSettings {
  /// Creates a new [LocalTerminalAiSettings].
  const LocalTerminalAiSettings({required this.enabled});

  /// Whether the assistant is enabled.
  final bool enabled;

  /// Stable signature describing the active assistant configuration.
  String get signature => enabled ? 'enabled' : 'disabled';

  /// Returns a copy of this settings object with replacements applied.
  LocalTerminalAiSettings copyWith({bool? enabled}) =>
      LocalTerminalAiSettings(enabled: enabled ?? this.enabled);
}

/// Provider for the terminal AI assistant settings.
final localTerminalAiSettingsProvider =
    NotifierProvider<LocalTerminalAiSettingsNotifier, LocalTerminalAiSettings>(
      LocalTerminalAiSettingsNotifier.new,
    );

/// Notifier for persisted terminal AI assistant settings.
class LocalTerminalAiSettingsNotifier
    extends Notifier<LocalTerminalAiSettings> {
  late final SettingsService _settings;
  bool _disposed = false;

  @override
  LocalTerminalAiSettings build() {
    _settings = ref.watch(settingsServiceProvider);
    _disposed = false;
    ref.onDispose(() => _disposed = true);
    unawaited(Future<void>.microtask(_init));
    return const LocalTerminalAiSettings(enabled: false);
  }

  Future<void> _init() async {
    final enabled = await _settings.getBool(SettingKeys.localTerminalAiEnabled);
    if (_disposed) {
      return;
    }

    state = LocalTerminalAiSettings(enabled: enabled);
    unawaited(_syncRuntimeTargets());
  }

  /// Enables or disables the assistant.
  Future<void> setEnabled({required bool enabled}) async {
    await _settings.setBool(SettingKeys.localTerminalAiEnabled, value: enabled);
    state = state.copyWith(enabled: enabled);
    unawaited(_syncRuntimeTargets());
  }

  Future<void> _syncRuntimeTargets() async {
    if (_disposed) {
      return;
    }
    unawaited(
      ref.read(localTerminalAiManagedModelProvider.notifier).sync(state),
    );
  }
}
