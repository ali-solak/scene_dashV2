part of '../skills.dart';

/// Wind gust waiting for the leap to land.
final class PendingWindBlast {
  PendingWindBlast(this.power);

  /// Blast power at cast time.
  final double power;

  /// Seconds since the cast; the gust fires at `windCastSeconds`.
  double elapsed = 0;
}

/// Damage over time from fire.
final class Burning {
  Burning(this.damage);

  /// Damage per tick.
  final double damage;

  /// Seconds since the last damage tick.
  double sinceTick = 0;
}

/// Lava pool on the ground.
final class LavaPit {
  LavaPit(this.damage);

  /// Damage per tick.
  final double damage;

  double sinceTick = 0;

  /// Seconds since the pit opened; drives the material's swell-in.
  double elapsed = 0;
}

/// Active shield barrier.
final class Barrier {
  Barrier(this.charges) : maxCharges = charges;

  /// Blocks left.
  int charges;

  /// Initial block count.
  final int maxCharges;

  /// Seconds since the last block.
  double sinceBlock = double.infinity;

  /// Direction of the last hit.
  final Vector3 hitFrom = Vector3(0, 0, 1);

  bool get spent => charges <= 0;

  /// Absorbs one hit and returns whether the barrier is spent.
  bool absorb({Vector3? push}) {
    charges--;
    sinceBlock = 0;
    if (push != null && push.x * push.x + push.z * push.z > 1e-9) {
      // Keep the ripple on the shell equator.
      hitFrom
        ..setValues(-push.x, 0, -push.z)
        ..normalize();
    }
    return spent;
  }
}

/// Shield scene nodes.
final class BarrierVisual {
  BarrierVisual({required this.sphere, required this.material, this.arm});

  final Node sphere;

  /// Bubble material.
  final Material material;

  /// Bubble animation time.
  double elapsed = 0;

  /// Shield model attached to the arm.
  final Node? arm;
}

/// Flame attached to a burning body.
final class BurnFlame {
  const BurnFlame(this.node);

  final Node node;
}
