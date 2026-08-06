/// Shared actor components.
library;

import 'dart:math' as math;

import 'package:scene_dash_v2/scene_dash_v2.dart' show Entity, Tag;
import 'package:vector_math/vector_math.dart' show Vector3, Vector4;

final class Player implements Tag {
  const Player();
}

final class PlayerWindup {
  const PlayerWindup(this.facing);
  final double facing;
}

final class HitLanded {
  const HitLanded(
    this.target,
    this.damage, {
    this.heavy = false,
    this.knockback,
    this.stagger = true,
    this.impact = true,
  });

  final Entity target;
  final double damage;
  final bool heavy;
  final Vector3? knockback;
  final bool stagger;
  final bool impact;
}

final class CastLeap {
  const CastLeap();
}

final class Health {
  Health(this.max) : current = max;

  double max;
  double current;

  bool get alive => current > 0;

  void heal(double amount) {
    if (!alive) return;
    current = math.min(max, current + amount);
  }
}

const double knockbackGravity = 18;

const double launchDownedSeconds = 1.0;

final class Knockback {
  Knockback({this.decayRate = 7, this.gravity = knockbackGravity});

  final Vector3 velocity = Vector3.zero();
  final double decayRate;
  final double gravity;

  bool airborne = false;
  double downed = 0;

  /// True while airborne or recovering on the ground.
  bool get incapacitated => airborne || downed > 0;

  void shove(Vector3 push) {
    velocity.setFrom(push);
    if (push.y > 0) airborne = true;
  }

  void step(double dt, Vector3 into) {
    if (airborne || into.y > 0) {
      velocity.y -= gravity * dt;
      into.y += velocity.y * dt;
      if (into.y <= 0) {
        into.y = 0;
        velocity.y = 0;
        if (airborne) downed = launchDownedSeconds;
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

/// Scorch marks pushed to the grass material.
final class GrassBurns {
  static const int slots = 4;

  /// (world x, world z, radius, strength)
  final List<Vector4> marks = List<Vector4>.generate(
    slots,
    (_) => Vector4.zero(),
  );
  int _next = 0;

  void scorch(double x, double z, double radius) {
    marks[_next].setValues(x, z, radius, 1);
    _next = (_next + 1) % slots;
  }

  void regrow(double dt, double seconds) {
    var live = false;
    for (final mark in marks) {
      if (mark.w > 0) {
        mark.w = math.max(0, mark.w - dt / seconds);
        live = true;
      }
    }
    active = live;
  }

  bool active = false;
}
