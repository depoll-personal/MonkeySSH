import 'package:dartssh2/src/algorithm/ssh_cipher_type.dart';
import 'package:dartssh2/src/algorithm/ssh_hostkey_type.dart';
import 'package:dartssh2/src/algorithm/ssh_kex_type.dart';
import 'package:dartssh2/src/algorithm/ssh_mac_type.dart';

abstract class SSHAlgorithm {
  /// The name of the algorithm.
  String get name;

  const SSHAlgorithm();

  @override
  String toString() {
    return '$runtimeType($name)';
  }
}

extension SSHAlgorithmList<T extends SSHAlgorithm> on List<T> {
  List<String> toNameList() {
    return map((algorithm) => algorithm.name).toList();
  }

  T? getByName(String name) {
    for (var algorithm in this) {
      if (algorithm.name == name) {
        return algorithm;
      }
    }
    return null;
  }
}

class SSHAlgorithms {
  static const _defaultHostkey = [
    SSHHostkeyType.ed25519,
    SSHHostkeyType.rsaSha512,
    SSHHostkeyType.rsaSha256,
    SSHHostkeyType.rsaSha1,
    SSHHostkeyType.ecdsa521,
    SSHHostkeyType.ecdsa384,
    SSHHostkeyType.ecdsa256,
  ];

  static const _defaultCipher = [
    SSHCipherType.aes128ctr,
    SSHCipherType.aes128cbc,
    SSHCipherType.aes256ctr,
    SSHCipherType.aes256cbc,
  ];

  static const _defaultMac = [
    SSHMacType.hmacSha256_96,
    SSHMacType.hmacSha512_96,
    SSHMacType.hmacSha256Etm,
    SSHMacType.hmacSha512Etm,
    SSHMacType.hmacSha1,
    SSHMacType.hmacSha256,
    SSHMacType.hmacSha512,
    SSHMacType.hmacMd5,
  ];

  static const _defaultKex = [
    SSHKexType.mlkem768X25519,
    SSHKexType.x25519,
    SSHKexType.nistp521,
    SSHKexType.nistp384,
    SSHKexType.nistp256,
    SSHKexType.dhGexSha256,
    SSHKexType.dh14Sha256,
    SSHKexType.dh14Sha1,
    SSHKexType.dhGexSha1,
    SSHKexType.dh1Sha1,
  ];

  /// Algorithm used for the key exchange.
  final List<SSHKexType> kex;

  /// Algorithm used for the host key.
  final List<SSHHostkeyType> hostkey;

  /// Algorithm used for the encryption.
  final List<SSHCipherType> cipher;

  /// Algorithm used for the authentication.
  final List<SSHMacType> mac;

  const SSHAlgorithms({
    this.kex = _defaultKex,
    this.hostkey = _defaultHostkey,
    this.cipher = _defaultCipher,
    this.mac = _defaultMac,
  });

  static List<SSHKexType> preferredKex({bool includeSntrup761 = false}) {
    return [
      SSHKexType.mlkem768X25519,
      if (includeSntrup761) SSHKexType.sntrup761X25519,
      if (includeSntrup761) SSHKexType.sntrup761X25519OpenSsh,
      ..._defaultKex.where(
        (algorithm) => algorithm != SSHKexType.mlkem768X25519,
      ),
    ];
  }
}
