/// Arena bounds.
library;

import 'dart:math' as math;

import 'package:vector_math/vector_math.dart' show Vector3;

import 'config.dart';

/// Clamps [position] to the arena and returns whether it changed.
bool clampToArena(Vector3 position) {
  final r = math.sqrt(position.x * position.x + position.z * position.z);
  if (r <= arenaBoundsRadius) return false;
  final scale = arenaBoundsRadius / r;
  position.x *= scale;
  position.z *= scale;
  return true;
}
