/// Frame-rate independent easing toward a moving target.
library;

import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

/// The blend factor that closes half the remaining gap every [halfLife]
/// seconds, for `value += (target - value) * blend`.
///
/// Independent of frame rate: two 8ms steps land exactly where one 16ms step
/// does, and a hitched 200ms frame eases rather than snapping. The naive
/// `value += (target - value) * dt * k` does neither. It drifts with the frame
/// rate and snaps once `dt` passes `1 / k`.
///
/// Reach for this over [smoothTo] whenever the gap is not plain subtraction:
/// a wrapped angle, a `Vector3` written in place, a quaternion.
///
/// ```dart
/// rig.yaw += angleDifference(desired, rig.yaw)
///          * smoothBlend(dt, cameraYawHalfLife);
/// ```
double smoothBlend(double dt, double halfLife) {
  assert(
    halfLife > 0,
    'smoothBlend needs a positive halfLife: it is the number of seconds the '
    'value takes to close half the remaining gap. A zero half-life means '
    '"arrive instantly", so assign the target directly instead.',
  );
  // Guards release builds too: 0/0 is NaN, which would poison the value
  // permanently with nothing thrown to point at the cause.
  if (halfLife <= 0) return 1;
  return 1 - math.exp(-dt * math.ln2 / halfLife);
}

/// Moves [value] toward [target], closing half the gap every [halfLife]
/// seconds.
///
/// Asymptotic: it approaches without ever arriving, which is what a camera
/// follow wants. Use [moveToward] when the value must actually reach the
/// target, such as an animation cross-fade weight.
double smoothTo(double value, double target, double dt, double halfLife) =>
    value + (target - value) * smoothBlend(dt, halfLife);

/// Moves [value] toward [target] by at most [maxDelta], arriving exactly.
///
/// A constant rate, not an asymptote: pass `dt / seconds` to cover the whole
/// span in [seconds]. The right call for cross-fade weights, where a clip at
/// 0.999 is still a clip being evaluated.
double moveToward(double value, double target, double maxDelta) {
  final gap = target - value;
  if (gap.abs() <= maxDelta) return target;
  return gap.isNegative ? value - maxDelta : value + maxDelta;
}

/// A value that eases toward a moving target and remembers its own rate.
///
/// Prefer plain [smoothTo] when a component already has a field to hold the
/// value. Most gameplay code does, and a plain `double` field stays plain data
/// that serialises and inspects without unwrapping. Reach for [GameSmooth]
/// when the smoother should own its state.
///
/// The target is passed per [tick] rather than stored, because it is normally
/// recomputed from world state every frame; a stored target is a second copy
/// that can go stale.
final class GameSmooth {
  /// A smoother resting at [initial].
  GameSmooth(double initial, {this.halfLife = 0.1})
    : _value = initial,
      assert(halfLife > 0, 'GameSmooth needs a positive halfLife.');

  /// Seconds to close half the remaining gap. Smaller is snappier.
  ///
  /// Mutable, so a camera can run loose during an intro and tighten once
  /// gameplay starts.
  double halfLife;

  double _value;

  /// The current value.
  double get value => _value;

  /// Jumps to [v] with no easing, for teleports, respawns and scene loads.
  void snap(double v) => _value = v;

  /// Eases toward [target] by [dt] seconds.
  void tick(double dt, double target) =>
      _value = smoothTo(_value, target, dt, halfLife);

  /// Whether [value] is within [epsilon] of [target].
  ///
  /// Exponential smoothing never exactly arrives, so "done" is a tolerance in
  /// the value's own units. [epsilon] is required on purpose: no single
  /// default is right for both a 0..1 opacity and a camera position in metres,
  /// and a shared default guarantees one caller is wrong without ever learning
  /// it.
  bool settled(double target, double epsilon) =>
      (target - _value).abs() <= epsilon;

  /// Value and rate, e.g. `0.42 (half-life 0.10s)`.
  @override
  String toString() =>
      '${_value.toStringAsFixed(2)} '
      '(half-life ${halfLife.toStringAsFixed(2)}s)';
}

/// Frame-rate independent easing for vectors.
extension Vector3Smoothing on Vector3 {
  /// Eases this vector toward [target] in place, closing half the gap every
  /// [halfLife] seconds.
  ///
  /// Writes into the receiver and allocates nothing, so it is safe on a
  /// per-entity path.
  void smoothToward(Vector3 target, double dt, double halfLife) {
    final blend = smoothBlend(dt, halfLife);
    setValues(
      x + (target.x - x) * blend,
      y + (target.y - y) * blend,
      z + (target.z - z) * blend,
    );
  }
}
