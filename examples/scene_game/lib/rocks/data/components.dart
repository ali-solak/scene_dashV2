part of '../rocks.dart';

/// Tags any rock entity.
final class Rock implements Tag {
  const Rock();
}

/// Tags the faster, on-fire rocks; only they get [RockTrails] puffs.
final class Flaming implements Tag {
  const Flaming();
}

/// The rock's hit-flash shell node, a child of the physics-driven root so
/// the Rapier transform sync never disturbs it. Only its scale changes, so
/// the flash material stays shared — mutating it would flash every rock.
final class RockVisuals {
  const RockVisuals(this.shell);

  final Node shell;
}

/// Transient hit-reaction state, inserted when a projectile connects and
/// removed when the flash finishes.
final class RockHitReaction {
  RockHitReaction({required this.strength});

  final GameTimer flash = GameTimer(rockHitReactionDuration);
  final double strength;
}
