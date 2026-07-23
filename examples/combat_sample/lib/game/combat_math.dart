/// Planar combat geometry, shared by the sword, the axes, the skills and
/// both movement systems — one authoritative definition each for
/// distance, reach + arc, knockback direction, angle wrapping and prone
/// settling, so the player, enemy and skill behaviors can never drift
/// apart on the math itself. Tuning constants stay per feature.
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

/// Reach + frontal arc: whether [to] stands within [reach] of [from] and
/// inside ±[halfArc] of [facing] — the one test behind the sword's swing,
/// the barbarian's axe and the fire gush's cone.
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

/// The world-space shove a connect delivers: straight out along
/// [from] → [to], at [speed].
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

/// Turns [from] toward [to] by at most [maxDelta] radians, shortest arc.
double turnToward(double from, double to, double maxDelta) {
  final difference = angleDifference(to, from);
  if (difference.abs() <= maxDelta) return to;
  return from + difference.sign * maxDelta;
}

/// Eases a thrown fighter's tumble down onto its back: the flop at the
/// end of the arc, not a lie-down. [rate] is the owner's settle tuning.
double towardProne(double tumble, double dt, {required double rate}) {
  const prone = math.pi / 2;
  final step = rate * dt;
  if ((prone - tumble).abs() <= step) return prone;
  return tumble + (prone - tumble).sign * step;
}
