import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:monkeyssh/app/theme.dart';

void main() {
  group('FluttyTheme', () {
    test('allows helper text to wrap in light theme', () {
      expect(
        FluttyTheme.buildInputDecorationTheme(Brightness.light).helperMaxLines,
        3,
      );
    });

    test('allows helper text to wrap in dark theme', () {
      expect(
        FluttyTheme.buildInputDecorationTheme(Brightness.dark).helperMaxLines,
        3,
      );
    });
  });
}
