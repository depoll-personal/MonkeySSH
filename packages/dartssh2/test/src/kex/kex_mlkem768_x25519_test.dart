// @dart=3.0

import 'dart:typed_data';

import 'package:dartssh2/src/kex/kex_mlkem768_x25519.dart';
import 'package:dartssh2/src/kex/kex_x25519.dart';
import 'package:dartssh2/src/ssh_kex_utils.dart';
import 'package:pqcrypto/pqcrypto.dart';
import 'package:pointycastle/export.dart';
import 'package:test/test.dart';

void main() {
  test('SSHKexMlkem768X25519 matches OpenSSH-style hybrid secret derivation',
      () {
    final clientKex = SSHKexMlkem768X25519();
    final clientPublicKey = clientKex.publicKey;
    final mlkemPublicKey = Uint8List.sublistView(
      clientPublicKey,
      0,
      SSHKexMlkem768X25519.publicKeyLength,
    );
    final x25519PublicKey = Uint8List.sublistView(
      clientPublicKey,
      SSHKexMlkem768X25519.publicKeyLength,
    );

    final (ciphertext, kemSharedSecret) = PqcKem.kyber768.encapsulate(
      mlkemPublicKey,
    );
    final serverX25519 = SSHKexX25519();
    final x25519SharedSecret = serverX25519.computeRawSecret(x25519PublicKey);
    final expectedEncoding = SSHKexUtils.encodeBinarySharedSecret(
      SSHKexUtils.hashSharedSecret(
        digest: SHA256Digest(),
        parts: [kemSharedSecret, x25519SharedSecret],
      ),
    );
    final serverPublicKey = Uint8List(
      ciphertext.length + serverX25519.publicKey.length,
    )
      ..setRange(0, ciphertext.length, ciphertext)
      ..setRange(
        ciphertext.length,
        ciphertext.length + serverX25519.publicKey.length,
        serverX25519.publicKey,
      );

    expect(clientKex.computeSecretEncoding(serverPublicKey), expectedEncoding);
  });
}
