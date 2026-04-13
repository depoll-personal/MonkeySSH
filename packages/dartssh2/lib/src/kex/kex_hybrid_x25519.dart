import 'dart:typed_data';

import 'package:dartssh2/src/kex/kex_x25519.dart';
import 'package:dartssh2/src/ssh_kex.dart';
import 'package:dartssh2/src/ssh_kex_utils.dart';
import 'package:pointycastle/export.dart';

abstract class SSHKexHybridX25519 implements SSHKexECDH {
  SSHKexHybridX25519({
    required this.kemCiphertextLength,
    required Digest Function() digestFactory,
    required Uint8List kemPublicKey,
    required Uint8List kemSecretKey,
    required SSHKexX25519 x25519,
  })  : _digestFactory = digestFactory,
        _kemSecretKey = Uint8List.fromList(kemSecretKey),
        _x25519 = x25519,
        publicKey = _composePublicKey(kemPublicKey, x25519.publicKey);

  final int kemCiphertextLength;
  final Digest Function() _digestFactory;
  final Uint8List _kemSecretKey;
  final SSHKexX25519 _x25519;

  @override
  final Uint8List publicKey;

  Uint8List decapsulate(Uint8List ciphertext, Uint8List secretKey);

  @override
  Uint8List computeSecretEncoding(Uint8List remotePublicKey) {
    final expectedLength = kemCiphertextLength + SSHKexX25519.publicKeyLength;
    if (remotePublicKey.length != expectedLength) {
      throw ArgumentError.value(
        remotePublicKey,
        'remotePublicKey',
        'must be $expectedLength bytes long',
      );
    }

    final kemCiphertext = Uint8List.sublistView(
      remotePublicKey,
      0,
      kemCiphertextLength,
    );
    final x25519PublicKey = Uint8List.sublistView(
      remotePublicKey,
      kemCiphertextLength,
    );
    final kemSharedSecret = decapsulate(kemCiphertext, _kemSecretKey);
    final x25519SharedSecret = _x25519.computeRawSecret(x25519PublicKey);
    final hybridSharedSecret = SSHKexUtils.hashSharedSecret(
      digest: _digestFactory(),
      parts: [kemSharedSecret, x25519SharedSecret],
    );
    return SSHKexUtils.encodeBinarySharedSecret(hybridSharedSecret);
  }

  static Uint8List _composePublicKey(
    Uint8List kemPublicKey,
    Uint8List x25519PublicKey,
  ) {
    final combined = Uint8List(
      kemPublicKey.length + x25519PublicKey.length,
    );
    combined
      ..setRange(0, kemPublicKey.length, kemPublicKey)
      ..setRange(
        kemPublicKey.length,
        combined.length,
        x25519PublicKey,
      );
    return combined;
  }
}
