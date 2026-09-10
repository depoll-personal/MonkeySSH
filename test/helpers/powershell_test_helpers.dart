import 'dart:convert';

/// Decodes an encoded PowerShell command independently of production encoding.
/// Commands without an encoded script are returned unchanged.
String decodeEncodedPowerShell(String command) {
  const marker = '-EncodedCommand ';
  final index = command.indexOf(marker);
  if (index < 0) return command;
  final bytes = base64.decode(command.substring(index + marker.length).trim());
  final buffer = StringBuffer();
  for (var i = 0; i + 1 < bytes.length; i += 2) {
    buffer.writeCharCode(bytes[i] | (bytes[i + 1] << 8));
  }
  return buffer.toString();
}
