import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Stores optional credentials used by the local terminal AI runtime.
class LocalTerminalAiCredentialsService {
  /// Creates a new [LocalTerminalAiCredentialsService].
  LocalTerminalAiCredentialsService({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _huggingFaceTokenKey =
      'flutty_local_terminal_ai_hugging_face_token';

  /// Returns the saved Hugging Face token, if one is available.
  Future<String?> getHuggingFaceToken() async {
    try {
      final token = await _storage.read(key: _huggingFaceTokenKey);
      final trimmedToken = token?.trim();
      if (trimmedToken == null || trimmedToken.isEmpty) {
        return null;
      }
      return trimmedToken;
    } on MissingPluginException {
      return null;
    }
  }

  /// Returns whether a non-empty Hugging Face token is saved.
  Future<bool> hasHuggingFaceToken() async =>
      (await getHuggingFaceToken()) != null;

  /// Saves the Hugging Face token for later gated-model downloads.
  Future<void> setHuggingFaceToken(String token) async {
    final trimmedToken = token.trim();
    if (trimmedToken.isEmpty) {
      throw ArgumentError.value(
        token,
        'token',
        'Hugging Face token cannot be empty.',
      );
    }
    await _storage.write(key: _huggingFaceTokenKey, value: trimmedToken);
  }

  /// Removes the saved Hugging Face token.
  Future<void> clearHuggingFaceToken() =>
      _storage.delete(key: _huggingFaceTokenKey);
}

/// Provider for [LocalTerminalAiCredentialsService].
final localTerminalAiCredentialsServiceProvider =
    Provider<LocalTerminalAiCredentialsService>(
      (ref) => LocalTerminalAiCredentialsService(),
    );

/// Provider for whether a Hugging Face token is saved for local AI downloads.
final localTerminalAiHasHuggingFaceTokenProvider = FutureProvider<bool>(
  (ref) => ref
      .watch(localTerminalAiCredentialsServiceProvider)
      .hasHuggingFaceToken(),
);
