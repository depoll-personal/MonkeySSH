// @dart=3.0

import 'dart:typed_data';

import 'package:dartssh2/src/algorithm/ssh_kex_type.dart';
import 'package:dartssh2/src/kex/kex_hybrid_x25519.dart';
import 'package:dartssh2/src/kex/kex_x25519.dart';
import 'package:pqcrypto/pqcrypto.dart';

class SSHKexMlkem768X25519 extends SSHKexHybridX25519 {
  factory SSHKexMlkem768X25519() {
    final (publicKey, secretKey) = PqcKem.kyber768.generateKeyPair();
    return SSHKexMlkem768X25519._(
      x25519: SSHKexX25519(),
      kemPublicKey: publicKey,
      kemSecretKey: secretKey,
    );
  }

  SSHKexMlkem768X25519._({
    required super.x25519,
    required super.kemPublicKey,
    required super.kemSecretKey,
  }) : super(
          kemCiphertextLength: ciphertextLength,
          digestFactory: SSHKexType.mlkem768X25519.digestFactory,
        );

  static const publicKeyLength = 1184;
  static const ciphertextLength = 1088;

  @override
  Uint8List decapsulate(Uint8List ciphertext, Uint8List secretKey) {
    return PqcKem.kyber768.decapsulate(secretKey, ciphertext);
  }
}
