import 'package:dartssh2/src/pq/sntrup761.dart';
import 'package:dartssh2/src/pq/sntrup761_types.dart';

class SSHPostQuantumSupport {
  static final Sntrup761Availability _sntrup761Availability =
      sntrup761Availability();

  static bool get isMlkem768X25519Available => true;

  static bool get isSntrup761X25519Available =>
      _sntrup761Availability.isAvailable;

  static String? get sntrup761X25519UnavailableReason =>
      _sntrup761Availability.unavailableReason;
}
