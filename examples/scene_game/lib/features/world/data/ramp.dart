/// Ramp geometry helpers for the scene game example.
library;

import 'dart:math' as math;

import 'config.dart';

/// World-space surface height of the ramp at depth [z].
double rampSurfaceYAtZ(double z) {
  return rampThickness * 0.5 * math.cos(rampInclineRadians) -
      z * math.sin(rampInclineRadians);
}

/// Whether (x, z) lies over the ramp's footprint.
bool isOverRampFootprint(double x, double z) {
  return x.abs() <= rampWidth * 0.5 && z.abs() <= rampLength * 0.5;
}
