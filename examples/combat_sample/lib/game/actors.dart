/// Shared actor vocabulary: the components every combat feature reads
/// (player, enemies, rules) without importing each other.
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

  /// Not final: the vitality upgrade raises the player's ceiling mid-run.
  double max;
  double current;

  bool get alive => current > 0;

  /// Heals up to the ceiling (never past it, never resurrects).
  void heal(double amount) {
    if (!alive) return;
    current = math.min(max, current + amount);
  }
}

/// Gravity on a knockback arc, in m/s^2. Weaker than real gravity so a
/// throw has visible hang time (`2 * launchSpeed / gravity`). Every
/// launch is tuned against this number; moving it retunes all of them.
const double knockbackGravity = 18;

/// How long a launched body lies on the floor after it lands, before it
/// is allowed to get up.
const double launchDownedSeconds = 1.0;

/// The shove a connect puts on its victim, the physical half of hit
/// feedback. `applyDamage` sets it; the movement systems integrate and
/// decay it, so a heavy visibly throws the target backward.
final class Knockback {
  Knockback({this.decayRate = 7, this.gravity = knockbackGravity});

  /// Horizontal components are a decaying shove; [velocity.y] is a real
  /// ballistic launch (a giant's blow throws you into the air).
  final Vector3 velocity = Vector3.zero();
  final double decayRate;
  final double gravity;

  /// Off the ground (mid-launch): movement input has no purchase.
  bool airborne = false;

  /// Seconds still to spend on the floor after landing. Without this,
  /// launched bodies popped upright the instant they touched down.
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
      // The decay models ground friction, sliding to a stop, so it only
      // applies while grounded. Decaying mid-flight killed the horizontal
      // half of every launch, turning a throw into a hop.
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
