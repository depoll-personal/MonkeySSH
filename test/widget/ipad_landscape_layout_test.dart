import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monkeyssh/presentation/widgets/ipad_landscape_layout.dart';

void main() {
  group('shouldUseLargeScreenMasterDetail', () {
    test('enables master-detail on iPad landscape', () {
      expect(
        shouldUseLargeScreenMasterDetail(
          orientation: Orientation.landscape,
          screenSize: const Size(1194, 834),
        ),
        isTrue,
      );
    });

    test('enables master-detail on Android tablets', () {
      expect(
        shouldUseLargeScreenMasterDetail(
          orientation: Orientation.landscape,
          screenSize: const Size(1280, 800),
        ),
        isTrue,
      );
    });

    test('enables master-detail on desktop-sized windows', () {
      expect(
        shouldUseLargeScreenMasterDetail(
          orientation: Orientation.landscape,
          screenSize: const Size(1440, 900),
        ),
        isTrue,
      );
    });

    test('disables master-detail on portrait tablets', () {
      expect(
        shouldUseLargeScreenMasterDetail(
          orientation: Orientation.portrait,
          screenSize: const Size(834, 1194),
        ),
        isFalse,
      );
    });

    test('disables master-detail on phone landscape widths', () {
      expect(
        shouldUseLargeScreenMasterDetail(
          orientation: Orientation.landscape,
          screenSize: const Size(932, 430),
        ),
        isFalse,
      );
    });
  });

  group('shouldUseIpadLandscapeMasterDetail', () {
    test('enables the iPad shell on iPad landscape', () {
      expect(
        shouldUseIpadLandscapeMasterDetail(
          platform: TargetPlatform.iOS,
          orientation: Orientation.landscape,
          screenSize: const Size(1194, 834),
        ),
        isTrue,
      );
    });

    test('disables the iPad shell on iPad portrait', () {
      expect(
        shouldUseIpadLandscapeMasterDetail(
          platform: TargetPlatform.iOS,
          orientation: Orientation.portrait,
          screenSize: const Size(834, 1194),
        ),
        isFalse,
      );
    });

    test('disables the iPad shell on iPhone landscape widths', () {
      expect(
        shouldUseIpadLandscapeMasterDetail(
          platform: TargetPlatform.iOS,
          orientation: Orientation.landscape,
          screenSize: const Size(932, 430),
        ),
        isFalse,
      );
    });

    test('disables the iPad shell on Android tablets', () {
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
