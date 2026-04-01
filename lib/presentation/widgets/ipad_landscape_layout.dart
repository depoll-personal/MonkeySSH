import 'package:flutter/widgets.dart';

const _minimumIpadShortestSide = 744.0;

/// Whether the current window should use the large-screen master-detail UI.
bool shouldUseLargeScreenMasterDetail({
  required Orientation orientation,
  required Size screenSize,
}) =>
    orientation == Orientation.landscape &&
    screenSize.shortestSide >= _minimumIpadShortestSide;

/// Whether the current device should use the iPad-specific landscape shell.
bool shouldUseIpadLandscapeMasterDetail({
  required TargetPlatform platform,
  required Orientation orientation,
  required Size screenSize,
}) =>
    platform == TargetPlatform.iOS &&
    shouldUseLargeScreenMasterDetail(
      orientation: orientation,
      screenSize: screenSize,
    );
