import 'dart:typed_data';

import 'package:oqs/oqs.dart';

import 'sntrup761_types.dart';

const _algorithmName = 'sntrup761';

Sntrup761Availability sntrup761Availability() {
  try {
    LibOQS.init();
    final isAvailable = LibOQS.isKEMSupported(_algorithmName);
    return Sntrup761Availability(
      isAvailable: isAvailable,
      unavailableReason: isAvailable
          ? null
          : 'liboqs does not expose the $_algorithmName KEM.',
    );
  } on LibraryLoadException catch (error) {
    return Sntrup761Availability(
      isAvailable: false,
      unavailableReason: error.toString(),
    );
  } on LibOQSException catch (error) {
    return Sntrup761Availability(
      isAvailable: false,
      unavailableReason: error.toString(),
    );
  }
}

Sntrup761KeyPair generateSntrup761KeyPair() {
  final kem = _createKem();
  try {
    final keyPair = kem.generateKeyPair();
    return Sntrup761KeyPair(
      publicKey: keyPair.publicKey,
      secretKey: keyPair.secretKey,
    );
  } finally {
    kem.dispose();
  }
}

Sntrup761EncapsulationResult encapsulateSntrup761(
  Uint8List publicKey,
) {
  final kem = _createKem();
  try {
    final result = kem.encapsulate(publicKey);
    return Sntrup761EncapsulationResult(
      ciphertext: result.ciphertext,
      sharedSecret: result.sharedSecret,
    );
  } finally {
    kem.dispose();
  }
}

Uint8List decapsulateSntrup761(Uint8List ciphertext, Uint8List secretKey) {
  final kem = _createKem();
  try {
    return kem.decapsulate(ciphertext, secretKey);
  } finally {
    kem.dispose();
  }
}

KEM _createKem() {
  final availability = sntrup761Availability();
  if (!availability.isAvailable) {
    throw UnsupportedError(
      availability.unavailableReason ??
          'sntrup761 is unavailable in the current liboqs runtime.',
    );
  }
  return KEM.create(_algorithmName)!;
}
