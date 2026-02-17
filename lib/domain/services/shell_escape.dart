/// Escapes [value] as a single POSIX shell argument.
///
/// This wraps the value in single quotes and safely escapes embedded single
/// quotes so the returned string can be interpolated into shell commands.
String shellEscape(String value) {
  if (value.isEmpty) {
    return '\'\'';
  }
  final escapedValue = value.replaceAll('\'', '\'\\\'\'');
  return '\'$escapedValue\'';
}
