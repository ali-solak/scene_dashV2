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

/// Hit-reaction state, inserted with `removeAfter:` so the framework owns
/// its lifetime and the flash system reads progress via `expiryOf`. A
/// second hit refreshes the deadline.
final class RockHitReaction {
  const RockHitReaction({required this.strength});

  final double strength;
}
