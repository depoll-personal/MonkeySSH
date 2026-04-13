import 'dart:typed_data';

/// Interface for a class that implements key exchange logic.
abstract class SSHKex {}

/// Interface for a class that implements ECDH key exchange.
abstract class SSHKexECDH implements SSHKex {
  /// Public key computed from the private key.
  Uint8List get publicKey;

  /// Computes the SSH-encoded shared secret contribution for this key exchange.
  ///
  /// Classical ECDH implementations return an SSH mpint encoding. Hybrid
  /// post-quantum KEX implementations return an SSH string encoding of the
  /// hashed hybrid secret, matching OpenSSH.
  Uint8List computeSecretEncoding(Uint8List remotePublicKey);
}
