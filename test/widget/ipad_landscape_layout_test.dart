import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monkeyssh/presentation/widgets/ipad_landscape_layout.dart';

void main() {
  group('shouldUseIpadLandscapeMasterDetail', () {
    test('enables master-detail on iPad landscape', () {
      expect(
        shouldUseIpadLandscapeMasterDetail(
          platform: TargetPlatform.iOS,
          orientation: Orientation.landscape,
          screenSize: const Size(1194, 834),
        ),
        isTrue,
      );
    });

    test('disables master-detail on iPad portrait', () {
      expect(
        shouldUseIpadLandscapeMasterDetail(
          platform: TargetPlatform.iOS,
          orientation: Orientation.portrait,
          screenSize: const Size(834, 1194),
        ),
        isFalse,
      );
    });

    test('disables master-detail on iPhone landscape widths', () {
      expect(
        shouldUseIpadLandscapeMasterDetail(
          platform: TargetPlatform.iOS,
          orientation: Orientation.landscape,
          screenSize: const Size(932, 430),
        ),
        isFalse,
      );
    });

    test('disables master-detail on Android tablets', () {
      expect(
        shouldUseIpadLandscapeMasterDetail(
          platform: TargetPlatform.android,
          orientation: Orientation.landscape,
          screenSize: const Size(1280, 800),
        ),
        isFalse,
      );
    });
  });
}
