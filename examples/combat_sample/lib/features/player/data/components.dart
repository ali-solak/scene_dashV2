part of '../player.dart';

/// Current player movement.
final class PlayerMotion {
  /// World-space velocity this step.
  final Vector3 velocity = Vector3.zero();

  /// The direction a roll committed to on entry (world space, unit).
  final Vector3 rollDirection = Vector3(0, 0, 1);

  /// Last movement direction.
  final Vector3 moveIntent = Vector3.zero();

  /// Yaw the model faces: forward is `(sin facing, 0, cos facing)`.
  double facing = 0;

  /// Airborne tumble angle.
  double tumble = 0;

  /// Whether the player is downed.
  bool downed = false;

  /// Whether a downed player is airborne.
  bool airborne = false;
}

/// Current lock target.
final class Target {
  final Entity entity;
  const Target(this.entity);
}

/// Blade trail scene handles.
final class BladeTrail {
  BladeTrail(this.trail);

  /// Rides a node at the blade tip; the engine records its world path.
  final TrailComponent trail;
}
