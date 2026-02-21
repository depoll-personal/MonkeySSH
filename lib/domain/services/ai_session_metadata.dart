import 'dart:convert';

import '../models/ai_cli_provider.dart';

/// Utility helpers for decoding and reading AI session metadata payloads.
abstract final class AiSessionMetadata {
  /// Decodes a JSON metadata string into a key-value map.
  static Map<String, dynamic> decode(String? raw) {
    if (raw == null || raw.isEmpty) {
      return const <String, dynamic>{};
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } on FormatException {
      return const <String, dynamic>{};
    }
    return const <String, dynamic>{};
  }

  /// Reads a non-empty string value for [key] from [metadata].
  static String? readString(Map<String, dynamic> metadata, String key) {
    final value = metadata[key];
    if (value is String && value.trim().isNotEmpty) {
      return value;
    }
    return null;
  }

  /// Reads an integer-like value for [key] from [metadata].
  static int? readInt(Map<String, dynamic> metadata, String key) {
    final value = metadata[key];
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value);
    }
    return null;
  }

  /// Resolves an [AiCliProvider] from metadata key `provider`.
  static AiCliProvider? readProvider(Map<String, dynamic> metadata) {
    final providerName = readString(metadata, 'provider');
    if (providerName == null) {
      return null;
    }
    for (final provider in AiCliProvider.values) {
      if (provider.name == providerName) {
        return provider;
      }
    }
    return null;
  }
}
