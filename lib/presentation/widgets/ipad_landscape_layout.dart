import 'package:flutter/widgets.dart';

const _minimumIpadShortestSide = 744.0;

/// Whether the current device should use the iPad landscape master-detail UI.
bool shouldUseIpadLandscapeMasterDetail({
  required TargetPlatform platform,
  required Orientation orientation,
  required Size screenSize,
}) =>
    platform == TargetPlatform.iOS &&
    orientation == Orientation.landscape &&
    screenSize.shortestSide >= _minimumIpadShortestSide;
