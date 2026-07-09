part of '../projectiles.dart';

final class Projectile {
  Projectile({this.charge = 0});

  /// Shot strength: `0.0` is a normal burst pellet; `(0, 1]` is a charged shot.
  /// Immutable for the projectile's life - hit force is derived from it.
  final double charge;

  /// Rock entities already hit by this charged projectile. Burst pellets
  /// despawn on first impact, so this remains empty for them. Keyed by
  /// [Entity] (index + generation), so a despawned rock's reused slot never
  /// aliases with a rock hit earlier in the flight.
  final Set<Entity> hitRocks = <Entity>{};

  bool get charged => charge > 0;
}
