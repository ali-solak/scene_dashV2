/// The arena-bounds clamp: fighters never leave the clearing. Movement is
/// kinematic (no character controller; physics exists for overlap queries
/// and grounding only), so the bound is enforced in Dart by the movement
/// systems, not by collider walls.
library;

import 'dart:math' as math;

import 'package:vector_math/vector_math.dart' show Vector3;

import 'config.dart';

/// Clamps [position] (in place) onto the horizontal disc of
/// [arenaBoundsRadius] around the origin. Y is untouched; grounding is the
/// physics query's job. Returns true when the position was out of bounds.
bool clampToArena(Vector3 position) {
  final r = math.sqrt(position.x * position.x + position.z * position.z);
  if (r <= arenaBoundsRadius) return false;
  final scale = arenaBoundsRadius / r;
  position.x *= scale;
  position.z *= scale;
  return true;
}
