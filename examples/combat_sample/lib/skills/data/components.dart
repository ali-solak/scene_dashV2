part of '../skills.dart';

/// A wind gust waiting for the leap to land. `castSkills` adds this and
/// starts the jump; `firePendingWindBlast` fires the blast once the leap
/// comes back down, so the gust reads as thrown down on landing.
final class PendingWindBlast {
  PendingWindBlast(this.power);

  /// The blast's level scale, captured at cast so a purchase mid-flight
  /// does not change the gust already in the air.
  final double power;

  /// Seconds since the cast; the gust fires at `windCastSeconds`.
  double elapsed = 0;
}

/// On fire: ticks damage until the framework's `removeAfter:` clock takes
/// the component off. Re-applying refreshes the clock rather than
/// stacking: one fire, longer.
final class Burning {
  Burning(this.damage);

  /// Damage per tick, scaled by the gush's level at cast time. Carried on
  /// the component so a purchase mid-burn does not retroactively change a
  /// fire already on a barbarian.
  final double damage;

  /// Seconds since the last damage tick.
  double sinceTick = 0;
}

/// A pool of lava on the ground. Lives on its own entity (position in
/// [SceneTransform], lifetime on a `DespawnAfter`) so the pit outlives
/// the cast and anything can walk into it.
final class LavaPit {
  LavaPit(this.damage);

  /// Damage per tick, scaled by the pit's level when it was opened (see
  /// the note on [Burning.damage]).
  final double damage;

  double sinceTick = 0;

  /// Seconds since the pit opened; drives the material's swell-in.
  double elapsed = 0;
}

/// The shield's barrier while it is up. Lives on the fighter it protects
/// (no position of its own, and it must be findable from a [HitLanded]
/// target). Presence is the state: `applyDamage` removes it on the blow
/// that spends the last charge, so "is the shield up" is one `tryGet`.
final class Barrier {
  Barrier(this.charges) : maxCharges = charges;

  /// Blocks left. Fixed at cast time from the skill's level, so buying a
  /// level while the barrier is up does not thicken the one you already
  /// paid for (see the note on [Burning.damage]).
  int charges;

  /// What it was raised with: the visual reads its brightness off the
  /// fraction remaining, and the HUD draws this many pips.
  final int maxCharges;

  /// Seconds since the last block, for the visual's flare. Starts spent
  /// so a freshly raised barrier is not born mid-flash.
  double sinceBlock = double.infinity;

  /// World-space direction from the fighter to where the last blow
  /// struck; the bubble's ripple expands from here. Written by gameplay,
  /// only read by the visual.
  final Vector3 hitFrom = Vector3(0, 0, 1);

  bool get spent => charges <= 0;

  /// Takes one blow, [push] being the shove it would have delivered
  /// (which points attacker → victim, so the impact is the other way).
  /// Returns whether that was the last charge.
  bool absorb({Vector3? push}) {
    charges--;
    sinceBlock = 0;
    if (push != null && push.x * push.x + push.z * push.z > 1e-9) {
      // Flattened: the ripple belongs on the shell's equator, and a
      // giant's blow carries a large vertical launch that would otherwise
      // throw the ring up over the pole.
      hitFrom
        ..setValues(-push.x, 0, -push.z)
        ..normalize();
    }
    return spent;
  }
}

/// The light sphere drawn around a shielded fighter, and the shield model
/// on its arm. Held so the system that raised them can take them back
/// off; like [BurnFlame], these ride a body and cannot own their lifetime.
final class BarrierVisual {
  BarrierVisual({required this.sphere, required this.material, this.arm});

  final Node sphere;

  /// The bubble's material: the authored `.fmat` when it loaded, else the
  /// plain unlit fallback. [setBarrierCharge] drives whichever it is.
  final Material material;

  /// The shell's own clock, for the shader's `time`. Its own rather than
  /// the world's so the ripple starts at zero when the barrier goes up.
  double elapsed = 0;

  /// The shield model parented to `handslot.l`, when the character assets
  /// loaded one. Null on the graybox capsule.
  final Node? arm;
}

/// The flame hanging on a burning body. Holds the node so the system can
/// take it back off again when the burn ends; the fire follows the
/// barbarian, so it cannot be an entity with its own lifetime.
final class BurnFlame {
  const BurnFlame(this.node);

  final Node node;
}
