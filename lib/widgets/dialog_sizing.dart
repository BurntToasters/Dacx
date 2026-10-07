import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Dialog width clamped to the window, keeping a 24px gutter on each side.
double dialogWidth(BuildContext context, double desired) {
  final available = MediaQuery.sizeOf(context).width - 48;
  return math.min(desired, math.max(280.0, available));
}

double dialogHeight(BuildContext context, double desired) {
  final available = MediaQuery.sizeOf(context).height - 120;
  return math.min(desired, math.max(160.0, available));
}
