/// Shared actor components.
library;

import 'dart:math' as math;

import 'package:scene_dash_v2/scene_dash_v2.dart' show Tag;
import 'package:vector_math/vector_math.dart' show Vector3;

/// Tags the player entity.
final class Player implements Tag {
  const Player();
}

final class Health {
  Health(this.max) : current = max;

  /// Maximum health.
  double max;
  double current;

  bool get alive => current > 0;

  /// Heals up to the ceiling (never past it, never resurrects).
  void heal(double amount) {
    if (!alive) return;
    current = math.min(max, current + amount);
  }
}

final class PlayerWindup {
  const PlayerWindup(this.facing);

  /// Committed attack yaw.
  final double facing;
}

const double knockbackGravity = 18;

const double launchDownedSeconds = 1.0;

final class Knockback {
  Knockback({this.decayRate = 7, this.gravity = knockbackGravity});

  final Vector3 velocity = Vector3.zero();
  final double decayRate;
  final double gravity;

  /// Off the ground (mid-launch): movement input has no purchase.
  bool airborne = false;

  /// Remaining time on the ground.
  double downed = 0;

  /// Airborne, or still on the floor from a landing. Nothing that reads
  /// this may act.
  bool get incapacitated => airborne || downed > 0;

  /// Replaces the current shove (a fresh hit wins, it does not stack).
  void shove(Vector3 push) {
    velocity.setFrom(push);
    if (push.y > 0) airborne = true;
  }

  /// Integrates one step into [into]: the horizontal shove decays, the
  /// vertical arc falls under gravity and lands back on the ground plane.
  void step(double dt, Vector3 into) {
    if (airborne || into.y > 0) {
      velocity.y -= gravity * dt;
      into.y += velocity.y * dt;
      if (into.y <= 0) {
        into.y = 0;
        velocity.y = 0;
        if (airborne) downed = launchDownedSeconds; // landed: stay down
        airborne = false;
      }
    } else {
      into.y = 0;
      if (downed > 0) downed = math.max(0, downed - dt);
    }
    if (velocity.x != 0 || velocity.z != 0) {
      into
        ..x += velocity.x * dt
        ..z += velocity.z * dt;
      // Apply friction while grounded.
      if (!airborne) {
        final decay = math.exp(-decayRate * dt);
        velocity.x *= decay;
        velocity.z *= decay;
        if (velocity.x.abs() < 1e-3) velocity.x = 0;
        if (velocity.z.abs() < 1e-3) velocity.z = 0;
      }
    }
  }

  void clear() {
    velocity.setZero();
    airborne = false;
    downed = 0;
  }
}
