part of '../player.dart';

// The Player tag and Health live in game/actors.dart (shared vocabulary:
// the enemies and rules features read them without importing this one).

/// Movement state written by [movePlayer] each fixed step and read by the
/// camera now and the animation mapper later (L2: the mapper reads
/// machine + velocity, never the reverse).
final class PlayerMotion {
  /// World-space velocity this step.
  final Vector3 velocity = Vector3.zero();

  /// The direction a roll committed to on entry (world space, unit).
  final Vector3 rollDirection = Vector3(0, 0, 1);

  /// The last non-zero movement input (world space, unit). A buffered roll
  /// can fire a frame or two after the press, when the stick may already
  /// be centred; this remembers where the fighter was heading.
  final Vector3 moveIntent = Vector3.zero();

  /// Yaw the model faces: forward is `(sin facing, 0, cos facing)`.
  double facing = 0;

  /// Pitch the body tumbles through while airborne from a giant's blow;
  /// the ragdoll read on an animated rig. Snaps to zero on landing (L2).
  double tumble = 0;

  /// Thrown, or still on the floor from it. Mirrors
  /// `Knockback.incapacitated` so the animator (which sees only the
  /// motion, not the entity) can hold the hit pose through the landing.
  bool downed = false;

  /// Still off the ground (a subset of [downed]): true through the arc,
  /// false the moment the body lands. The mapper falls on this and lies on
  /// the landing beat, so the two reads are different clips.
  bool airborne = false;
}

/// The lock: present on the player while a target is held. Re-add replaces
/// (latest-add-wins), remove releases.
final class Target {
  final Entity entity;
  const Target(this.entity);
}

/// The blade trail's handles: the weapon node to sample and the ribbon it
/// feeds. Alive for the whole run; the ribbon empties itself between
/// swings rather than being respawned.
final class BladeTrail {
  BladeTrail({required this.weapon, required this.trail});

  /// The weapon node, sampled in world space each frame.
  final Node weapon;

  final SwordTrail trail;
}
