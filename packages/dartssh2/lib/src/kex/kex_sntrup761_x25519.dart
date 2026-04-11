import 'dart:typed_data';

import 'package:dartssh2/src/algorithm/ssh_kex_type.dart';
import 'package:dartssh2/src/kex/kex_hybrid_x25519.dart';
import 'package:dartssh2/src/kex/kex_x25519.dart';
import 'package:dartssh2/src/pq/sntrup761.dart';

class SSHKexSntrup761X25519 extends SSHKexHybridX25519 {
  factory SSHKexSntrup761X25519() {
    final availability = sntrup761Availability();
    if (!availability.isAvailable) {
      throw UnsupportedError(
        availability.unavailableReason ??
            'sntrup761x25519 is unavailable in the current runtime.',
      );
    }
    final keyPair = generateSntrup761KeyPair();
    return SSHKexSntrup761X25519._(
      x25519: SSHKexX25519(),
      kemPublicKey: keyPair.publicKey,
      kemSecretKey: keyPair.secretKey,
    );
  }

  SSHKexSntrup761X25519._({
    required super.x25519,
    required super.kemPublicKey,
    required super.kemSecretKey,
  }) : super(
          kemCiphertextLength: ciphertextLength,
          digestFactory: SSHKexType.sntrup761X25519.digestFactory,
        );

  static const publicKeyLength = 1158;
  static const ciphertextLength = 1039;

  @override
  Uint8List decapsulate(Uint8List ciphertext, Uint8List secretKey) {
    return decapsulateSntrup761(ciphertext, secretKey);
  }
}
