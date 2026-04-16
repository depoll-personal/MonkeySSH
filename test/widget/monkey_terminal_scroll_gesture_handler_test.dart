@Tags(['xterm-legacy'])
library;

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'legacy xterm-based test suite skipped during ghostty_vte migration',
    () {},
    skip:
        'See ghostty_vte_flutter migration PR; xterm-backed coverage will be '
        'rewritten against the new controller/snapshot APIs.',
  );
}
