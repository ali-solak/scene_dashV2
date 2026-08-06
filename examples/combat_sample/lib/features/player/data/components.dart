part of '../player.dart';

final class PlayerMotion {
  final Vector3 velocity = Vector3.zero();

  /// Committed roll direction in world space.
  final Vector3 rollDirection = Vector3(0, 0, 1);

  final Vector3 moveIntent = Vector3.zero();

  /// Yaw the model faces: forward is `(sin facing, 0, cos facing)`.
  double facing = 0;

  double tumble = 0;
  bool downed = false;
  bool airborne = false;
}

final class Target {
  final Entity entity;
  const Target(this.entity);
}

final class BladeTrail {
  BladeTrail(this.trail);

  final TrailComponent trail;
}
