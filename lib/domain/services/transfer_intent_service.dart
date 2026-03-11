import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Service that consumes transfer payloads opened from external files.
class TransferIntentService {
  static const _channel = MethodChannel('xyz.depollsoft.monkeyssh/transfer');
  static const _duplicateDeliveryWindow = Duration(seconds: 5);
  static final _edgeWhitespacePattern = RegExp(r'^\s|\s$');
  final _incomingController = StreamController<String>.broadcast();
  final _recentLivePayloadFingerprints = <int, DateTime>{};
  bool _initialized = false;

  /// Stream of incoming transfer payloads forwarded by native platforms.
  Stream<String> get incomingPayloads {
    _ensureInitialized();
    return _incomingController.stream;
  }

  /// Returns and clears a pending incoming transfer payload, if any.
  Future<String?> consumeIncomingTransferPayload() async {
    _ensureInitialized();
    try {
      final payload = await _channel.invokeMethod<String>(
        'consumeIncomingTransferPayload',
      );
      final normalizedPayload = _normalizePayload(payload);
      if (normalizedPayload == null) {
        return null;
      }
      _pruneRecentLivePayloads();
      final fingerprint = _payloadFingerprint(normalizedPayload);
      final lastLiveDelivery = _recentLivePayloadFingerprints[fingerprint];
      if (lastLiveDelivery == null) {
        return normalizedPayload;
      }
      if (DateTime.now().difference(lastLiveDelivery) <=
          _duplicateDeliveryWindow) {
        return null;
      }
      _recentLivePayloadFingerprints.remove(fingerprint);
      return normalizedPayload;
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  void _ensureInitialized() {
    if (_initialized) {
      return;
    }
    _initialized = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'onIncomingTransferPayload') {
        return;
      }
      final payload = _normalizePayload(call.arguments);
      if (payload != null) {
        _pruneRecentLivePayloads();
        _recentLivePayloadFingerprints[_payloadFingerprint(payload)] =
            DateTime.now();
        _incomingController.add(payload);
      }
    });
  }

  String? _normalizePayload(Object? payload) {
    if (payload is! String) {
      return null;
    }
    if (payload.isEmpty) {
      return null;
    }
    if (!_edgeWhitespacePattern.hasMatch(payload)) {
      return payload;
    }
    final normalizedPayload = payload.trim();
    if (normalizedPayload.isEmpty) {
      return null;
    }
    return normalizedPayload;
  }

  int _payloadFingerprint(String payload) => Object.hash(
    payload.length,
    payload.hashCode,
    payload.codeUnitAt(0),
    payload.codeUnitAt(payload.length ~/ 2),
    payload.codeUnitAt(payload.length - 1),
  );

  void _pruneRecentLivePayloads() {
    final cutoff = DateTime.now().subtract(_duplicateDeliveryWindow);
    _recentLivePayloadFingerprints.removeWhere(
      (_, deliveredAt) => deliveredAt.isBefore(cutoff),
    );
  }

  /// Releases resources held by the service.
  Future<void> dispose() async {
    if (_initialized) {
      _channel.setMethodCallHandler(null);
    }
    await _incomingController.close();
  }
}

/// Provider for [TransferIntentService].
final transferIntentServiceProvider = Provider<TransferIntentService>((ref) {
  final service = TransferIntentService();
  ref.onDispose(() => unawaited(service.dispose()));
  return service;
});
