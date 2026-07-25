/// Shared planar combat geometry.
library;

import 'dart:math' as math;

import 'package:scene_dash_v2/scene_dash_v2.dart' show SceneTransform;
import 'package:vector_math/vector_math.dart' show Vector3;

/// Distance on the ground plane between two transforms.
double planarDistance(SceneTransform from, SceneTransform to) {
  final dx = to.translation.x - from.translation.x;
  final dz = to.translation.z - from.translation.z;
  return math.sqrt(dx * dx + dz * dz);
}

/// Whether [to] is within [reach] and the frontal arc from [from].
bool withinArc({
  required SceneTransform from,
  required double facing,
  required SceneTransform to,
  required double reach,
  required double halfArc,
}) {
  final dx = to.translation.x - from.translation.x;
  final dz = to.translation.z - from.translation.z;
  if (math.sqrt(dx * dx + dz * dz) > reach) return false;
  return angleDifference(math.atan2(dx, dz), facing).abs() <= halfArc;
}

/// A ground-plane shove from [from] toward [to].
Vector3 awayFrom(SceneTransform from, SceneTransform to, double speed) {
  final dx = to.translation.x - from.translation.x;
  final dz = to.translation.z - from.translation.z;
  final length = math.sqrt(dx * dx + dz * dz).clamp(1e-6, double.infinity);
  return Vector3(dx / length * speed, 0, dz / length * speed);
}

/// Signed shortest difference `a - b`, wrapped to `(-pi, pi]`.
double angleDifference(double a, double b) {
  var difference = (a - b) % (2 * math.pi);
  if (difference > math.pi) difference -= 2 * math.pi;
  if (difference < -math.pi) difference += 2 * math.pi;
  return difference;
}

/// Turns [from] toward [to] by at most [maxDelta] radians.
double turnToward(double from, double to, double maxDelta) {
  final difference = angleDifference(to, from);
  if (difference.abs() <= maxDelta) return to;
  return from + difference.sign * maxDelta;
}

/// Moves a tumble angle toward the prone pose.
double towardProne(double tumble, double dt, {required double rate}) {
  const prone = math.pi / 2;
  final step = rate * dt;
  if ((prone - tumble).abs() <= step) return prone;
  return tumble + (prone - tumble).sign * step;
}
