part of '../player.dart';

// The Player tag and Health live in game/actors.dart (shared vocabulary —
// the enemies and rules features read them without importing this one).

/// Movement state written by [movePlayer] each fixed step and read by the
/// camera now and the animation mapper later (L2: the mapper reads
/// machine + velocity, never the reverse).
final class PlayerMotion {
  /// World-space velocity this step.
  final Vector3 velocity = Vector3.zero();

  /// The direction a roll committed to on entry (world space, unit).
  final Vector3 rollDirection = Vector3(0, 0, 1);

  /// The last non-zero movement input (world space, unit). A roll is
  /// BUFFERED, so it can fire a frame or two after the press — by then
  /// the stick may already be centred. This remembers where the fighter
  /// was actually heading so the dash still goes there.
  final Vector3 moveIntent = Vector3.zero();

  /// Yaw the model faces: forward is `(sin facing, 0, cos facing)`.
  double facing = 0;

  /// Pitch the body tumbles through while a giant's blow has you in the
  /// air — the ragdoll read on a rig that is animated, not simulated.
  /// Snaps back to zero on landing (stagger snaps, L2).
  double tumble = 0;

  /// Thrown, or still on the floor from it. Mirrors
  /// `Knockback.incapacitated` so the animator — which sees only the
  /// motion, not the entity — can hold the hit pose for the whole
  /// ragdoll, landing beat included.
  bool downed = false;
}

/// The lock: present on the player while a target is held. Re-add replaces
/// (latest-add-wins), remove releases.
final class Target {
  final Entity entity;
  const Target(this.entity);
}

/// The blade trail's handles: the sword node to sample and the ribbon it
/// feeds. One per fighter, alive for the whole run — the ribbon empties
/// itself between swings rather than being respawned.
final class BladeTrail {
  BladeTrail({required this.sword, required this.trail});

  /// The weapon node, sampled in world space each frame.
  final Node sword;

  final SwordTrail trail;
}
