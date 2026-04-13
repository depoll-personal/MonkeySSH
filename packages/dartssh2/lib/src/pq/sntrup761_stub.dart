import 'dart:typed_data';

import 'sntrup761_types.dart';

const _unavailableReason =
    'sntrup761x25519 requires a native liboqs runtime and is unavailable on '
    'this platform.';

Sntrup761Availability sntrup761Availability() => const Sntrup761Availability(
      isAvailable: false,
      unavailableReason: _unavailableReason,
    );

Never _unsupported() => throw UnsupportedError(_unavailableReason);

Sntrup761KeyPair generateSntrup761KeyPair() => _unsupported();

Sntrup761EncapsulationResult encapsulateSntrup761(
  Uint8List publicKey,
) =>
    _unsupported();

Uint8List decapsulateSntrup761(Uint8List ciphertext, Uint8List secretKey) =>
    _unsupported();
