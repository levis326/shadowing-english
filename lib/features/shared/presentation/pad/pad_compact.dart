import 'package:flutter/material.dart';

extension PadCompactLayout on BuildContext {
  bool get isPadCompact => MediaQuery.sizeOf(this).width < 1280;

  double get padPagePadding => isPadCompact ? 20 : 28;

  double get padSectionGap => isPadCompact ? 16 : 24;

  double get padCardRadius => isPadCompact ? 18 : 22;
}
