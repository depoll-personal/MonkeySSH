import 'dart:typed_data';

import 'package:dartssh2/src/kex/kex_sntrup761_x25519.dart';
import 'package:dartssh2/src/kex/kex_x25519.dart';
import 'package:dartssh2/src/pq/sntrup761.dart';
import 'package:dartssh2/src/ssh_kex_utils.dart';
import 'package:pointycastle/export.dart';
import 'package:test/test.dart';

void main() {
  final availability = sntrup761Availability();

  test(
    'SSHKexSntrup761X25519 matches OpenSSH-style hybrid secret derivation',
    () {
      final clientKex = SSHKexSntrup761X25519();
      final clientPublicKey = clientKex.publicKey;
      final sntrupPublicKey = Uint8List.sublistView(
        clientPublicKey,
        0,
        SSHKexSntrup761X25519.publicKeyLength,
      );
      final x25519PublicKey = Uint8List.sublistView(
        clientPublicKey,
        SSHKexSntrup761X25519.publicKeyLength,
      );

      final encapsulation = encapsulateSntrup761(sntrupPublicKey);
      final serverX25519 = SSHKexX25519();
      final x25519SharedSecret = serverX25519.computeRawSecret(x25519PublicKey);
      final expectedEncoding = SSHKexUtils.encodeBinarySharedSecret(
        SSHKexUtils.hashSharedSecret(
          digest: SHA512Digest(),
          parts: [
            encapsulation.sharedSecret,
            x25519SharedSecret,
          ],
        ),
      );
      final serverPublicKey = Uint8List(
        encapsulation.ciphertext.length + serverX25519.publicKey.length,
      )
        ..setRange(0, encapsulation.ciphertext.length, encapsulation.ciphertext)
        ..setRange(
          encapsulation.ciphertext.length,
          encapsulation.ciphertext.length + serverX25519.publicKey.length,
          serverX25519.publicKey,
        );

      expect(
        clientKex.computeSecretEncoding(serverPublicKey),
        expectedEncoding,
      );
    },
    skip: availability.isAvailable ? false : availability.unavailableReason,
  );
}
