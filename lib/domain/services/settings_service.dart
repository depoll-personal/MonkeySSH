import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/database.dart';

/// Keys for app settings.
abstract final class SettingKeys {
  /// Theme mode: 'system', 'light', 'dark'.
  static const themeMode = 'theme_mode';

  /// Terminal font family.
  static const terminalFont = 'terminal_font';

  /// Terminal font size.
  static const terminalFontSize = 'terminal_font_size';

  /// Terminal color scheme name.
  static const terminalColorScheme = 'terminal_color_scheme';

  /// Enable haptic feedback.
  static const hapticFeedback = 'haptic_feedback';

  /// Keyboard toolbar configuration.
  static const keyboardToolbar = 'keyboard_toolbar';

  /// Auto-reconnect on connection drop.
  static const autoReconnect = 'auto_reconnect';

  /// Keep-alive interval in seconds.
  static const keepAliveInterval = 'keep_alive_interval';

  /// Default SSH port.
  static const defaultPort = 'default_port';

  /// Default username.
  static const defaultUsername = 'default_username';
}

/// Service for managing app settings.
class SettingsService {
  /// Creates a new [SettingsService].
  SettingsService(this._db);

  final AppDatabase _db;

  /// Get a string setting.
  Future<String?> getString(String key) async {
    final result = await (_db.select(
      _db.settings,
    )..where((s) => s.key.equals(key))).getSingleOrNull();
    return result?.value;
  }

  /// Get an int setting.
  Future<int?> getInt(String key) async {
    final value = await getString(key);
    return value != null ? int.tryParse(value) : null;
  }

  /// Get a bool setting.
  Future<bool> getBool(String key, {bool defaultValue = false}) async {
    final value = await getString(key);
    if (value == 'true') return true;
    if (value == 'false') return false;
    return defaultValue;
  }

  /// Get a JSON setting.
  Future<Map<String, dynamic>?> getJson(String key) async {
    final value = await getString(key);
    if (value == null) return null;
    try {
      return jsonDecode(value) as Map<String, dynamic>;
    } on FormatException {
      return null;
    }
  }

  /// Set a string setting.
  Future<void> setString(String key, String value) async {
    await _db
        .into(_db.settings)
        .insertOnConflictUpdate(
          SettingsCompanion.insert(key: key, value: value),
        );
  }

  /// Set an int setting.
  Future<void> setInt(String key, int value) =>
      setString(key, value.toString());

  /// Set a bool setting.
  Future<void> setBool(String key, {required bool value}) =>
      setString(key, value.toString());

  /// Set a JSON setting.
  Future<void> setJson(String key, Map<String, dynamic> value) =>
      setString(key, jsonEncode(value));

  /// Delete a setting.
  Future<void> delete(String key) async {
    await (_db.delete(_db.settings)..where((s) => s.key.equals(key))).go();
  }

  /// Get all settings.
  Future<Map<String, String>> getAll() async {
    final results = await _db.select(_db.settings).get();
    return Map.fromEntries(results.map((s) => MapEntry(s.key, s.value)));
  }

  /// Watch a setting.
  Stream<String?> watchString(String key) => (_db.select(
    _db.settings,
  )..where((s) => s.key.equals(key))).watchSingleOrNull().map((s) => s?.value);
}

/// Provider for [SettingsService].
final settingsServiceProvider = Provider<SettingsService>(
  (ref) => SettingsService(ref.watch(databaseProvider)),
);

/// Provider for theme mode setting.
final themeModeProvider = FutureProvider<String>((ref) async {
  final settings = ref.watch(settingsServiceProvider);
  return await settings.getString(SettingKeys.themeMode) ?? 'system';
});
