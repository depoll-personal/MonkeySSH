import 'dart:typed_data';

class Sntrup761Availability {
  const Sntrup761Availability({
    required this.isAvailable,
    this.unavailableReason,
  });

  final bool isAvailable;
  final String? unavailableReason;
}

class Sntrup761KeyPair {
  const Sntrup761KeyPair({
    required this.publicKey,
    required this.secretKey,
  });

  final Uint8List publicKey;
  final Uint8List secretKey;
}

class Sntrup761EncapsulationResult {
  const Sntrup761EncapsulationResult({
    required this.ciphertext,
    required this.sharedSecret,
  });

  final Uint8List ciphertext;
  final Uint8List sharedSecret;
}
