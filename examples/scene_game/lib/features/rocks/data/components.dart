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
}

/// Transient hit-reaction state, inserted when a projectile connects with
/// `removeAfter: rockHitReactionDuration` — the framework drops it on
/// schedule (firing the shell-clearing observer), and the flash system
/// reads progress back through `expiryOf`. A second hit re-adds it, which
/// replaces the instance and refreshes the deadline.
final class RockHitReaction {
  const RockHitReaction({required this.strength});

  final double strength;
}
