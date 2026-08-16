/// `vector_math` interpolation for [GameTween].
library;

import 'package:flutter/animation.dart' show Curve;
import 'package:vector_math/vector_math.dart';

import 'tween.dart';

/// Linear interpolation between two positions. Allocates.
Vector3 lerpVector3(Vector3 from, Vector3 to, double t) => Vector3(
  from.x + (to.x - from.x) * t,
  from.y + (to.y - from.y) * t,
  from.z + (to.z - from.z) * t,
);

/// Linear interpolation between two RGBA colours. Allocates.
Vector4 lerpVector4(Vector4 from, Vector4 to, double t) => Vector4(
  from.x + (to.x - from.x) * t,
  from.y + (to.y - from.y) * t,
  from.z + (to.z - from.z) * t,
  from.w + (to.w - from.w) * t,
);

/// A tween between two positions.
///
/// [from] and [to] are copied, so a live vector like a `SceneTransform`
/// translation does not drag the tween along as it is mutated. `retarget`
/// stores the instance it is handed, so pass a copy there if the caller keeps
/// writing to it.
GameTween<Vector3> vector3Tween(
  Vector3 from,
  Vector3 to,
  double seconds, {
  Curve? curve,
}) => GameTween<Vector3>(
  from.clone(),
  to.clone(),
  seconds,
  lerp: lerpVector3,
  curve: curve,
);

/// A tween between two RGBA colours. Endpoints are copied, as in
/// [vector3Tween].
GameTween<Vector4> colorTween(
  Vector4 from,
  Vector4 to,
  double seconds, {
  Curve? curve,
}) => GameTween<Vector4>(
  from.clone(),
  to.clone(),
  seconds,
  lerp: lerpVector4,
  curve: curve,
);

/// Allocation-free reads for position tweens.
extension GameTweenVector3 on GameTween<Vector3> {
  /// Writes the current value into [out] without allocating.
  ///
  /// The read form for systems: [out] is usually a `Vector3` the caller
  /// already owns, such as a camera rig offset or a `SceneTransform`
  /// translation.
  void valueInto(Vector3 out) {
    final t = eased;
    final a = from;
    final b = to;
    out.setValues(
      a.x + (b.x - a.x) * t,
      a.y + (b.y - a.y) * t,
      a.z + (b.z - a.z) * t,
    );
  }
}

/// Allocation-free reads for colour tweens.
extension GameTweenVector4 on GameTween<Vector4> {
  /// Writes the current value into [out] without allocating.
  void valueInto(Vector4 out) {
    final t = eased;
    final a = from;
    final b = to;
    out.setValues(
      a.x + (b.x - a.x) * t,
      a.y + (b.y - a.y) * t,
      a.z + (b.z - a.z) * t,
      a.w + (b.w - a.w) * t,
    );
  }
}
