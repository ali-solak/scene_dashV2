part of '../rocks.dart';

/// Tags any rock entity.
final class Rock implements Tag {
  const Rock();
}

/// Tags the faster, on-fire rocks; only they get a flame-trail emitter.
final class Flaming implements Tag {
  const Flaming();
}

/// The rock's hit-flash shell node, a child of the physics-driven root so
/// the Rapier transform sync never disturbs it. Only its scale changes, so
/// the flash material stays shared — mutating it would flash every rock.
final class RockVisuals {
  RockVisuals(this.shell);

  final Node shell;

  /// The flame-trail emitter node while the rock is [Flaming], attached
  /// and removed by the `observe<Flaming>` pair. Null on plain rocks and
  /// in headless worlds (emitters need a scene).
  Node? trailEmitter;
}

/// Transient hit-reaction state, inserted when a projectile connects and
/// removed when the flash finishes.
final class RockHitReaction {
  RockHitReaction({required this.strength});

  final GameTimer flash = GameTimer(rockHitReactionDuration);
  final double strength;
}
