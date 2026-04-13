import 'dart:typed_data';

import 'sntrup761_stub.dart' if (dart.library.io) 'sntrup761_io.dart' as impl;
import 'sntrup761_types.dart';

Sntrup761Availability sntrup761Availability() => impl.sntrup761Availability();

Sntrup761KeyPair generateSntrup761KeyPair() => impl.generateSntrup761KeyPair();

Sntrup761EncapsulationResult encapsulateSntrup761(Uint8List publicKey) {
  return impl.encapsulateSntrup761(publicKey);
}

Uint8List decapsulateSntrup761(
  Uint8List ciphertext,
  Uint8List secretKey,
) {
  return impl.decapsulateSntrup761(ciphertext, secretKey);
}
