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

/// Builds a shell-safe `cd` target while preserving bare-home tilde expansion.
String buildShellCdDirectory(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    throw ArgumentError.value(
      value,
      'value',
      'Remote working directory cannot be empty.',
    );
  }
  if (trimmed == '~') {
    return '~';
  }
  if (trimmed.startsWith('~/')) {
    final rest = trimmed.substring(2);
    return rest.isEmpty ? '~' : '~/${shellEscape(rest)}';
  }
  return shellEscape(trimmed);
}
