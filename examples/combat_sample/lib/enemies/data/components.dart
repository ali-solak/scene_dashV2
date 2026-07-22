part of '../enemies.dart';

/// Tags every enemy entity.
final class Enemy implements Tag {
  const Enemy();
}

enum BrawlPhase {
  /// Climbing out of the ground on spawn (the floor-rise). Held still and
  /// harmless-looking until it finishes, then straight to [approach].
  rising,
  approach,
  circle,
  taunting,
  telegraph,
  swing,
  recover,
  staggered,
  dying,
}

/// The barbarian's brain: one [Machine] owns the mode (the readability
/// contract lives in its timings — a fixed telegraph always precedes a
/// swing). Rhythm constants are deliberately distinct from the player's.
final class Brawler {
  Brawler({
    required this.slot,
    required this.circleDirection,
    required this.wobbleSeed,
    this.power = 1,
    this.giant = false,
  }) : // Giants do not climb out of the ground — they walk in normal-sized
       // and swell on the transform clip, so a giant starts already up
       // (`approach`) and the awaken rise is for ordinary barbarians only.
       phase = Machine<BrawlPhase>(
         giant ? BrawlPhase.approach : BrawlPhase.rising,
       );

  /// Spawn index within the wave (drives the circle direction and wobble).
  final int slot;

  /// Damage/knockback multiplier — waves scale it, giants multiply it.
  final double power;

  /// A giant: bigger, tougher, and its blows launch the player.
  final bool giant;

  final Machine<BrawlPhase> phase;

  /// Seconds spent circling since the last taunt — the mid-fight taunt
  /// fires off this (see `brawlerDriver`), so the pack heckles on a timer
  /// instead of every frame.
  double sinceTaunt = 0;

  /// Seconds since the last connect that did not stagger — a fire-gush or
  /// lava tick. The mapper reads it for a brief flinch (mirrors the
  /// player's [Fighter.sinceHurt]); it gates nothing, so a body on fire
  /// still circles and swings. Starts spent.
  double sinceHurt = double.infinity;

  /// +1 or -1: which way this one circles the player.
  final double circleDirection;

  /// Phase offset for the circling radius wobble, so the pack breathes
  /// instead of orbiting in lockstep.
  final double wobbleSeed;

  /// Accumulated circling time driving the wobble (advanced by movement).
  double wobble = 0;

  /// Facing yaw; forward is `(sin facing, 0, cos facing)`. Frozen from the
  /// swing on, so a roll sidesteps a committed arc.
  double facing = 0;

  /// Pitch the body tumbles through while a wind blast has it in the air.
  /// Snaps flat on landing (L2: stagger snaps).
  double tumble = 0;

  /// Thrown, or still on the floor from it — mirrors
  /// `Knockback.incapacitated` for the animation mapper.
  bool downed = false;

  /// Still in the air (a subset of [downed]): true through the wind-blast
  /// arc, false once it lands. The mapper falls on this and lies on the
  /// landing beat — a real airborne pose instead of the death clip held
  /// stiff with its legs apart.
  bool airborne = false;

  /// Mirror of the coordinator's grant (single writer: [coordinateAggro]).
  /// The holder closes in and may telegraph; everyone else circles.
  bool hasToken = false;

  /// World-space velocity this step (written by movement, read by the
  /// animation mapper — L2's "machine + velocity" inputs).
  final Vector3 velocity = Vector3.zero();
}

/// slow down enemies in lava pit
final class Mired {
  const Mired();
}

/// A barbarian's in-world health bar (task 17): a `WidgetComponent`
/// surface on a child [node] above the head, its fill pushed each frame
/// into [fraction] and the node yaw-aimed at the camera.
final class EnemyHealthBar {
  EnemyHealthBar({required this.fraction, required this.node});

  final ValueNotifier<double> fraction;
  final Node node;

  /// Last fraction pushed — a DROP means a hit, which starts the punch.
  double lastFraction = 1;

  /// Seconds since the last hit, driving the scale-pop-and-tilt in
  /// [updateHealthBars]. Starts spent so a fresh bar sits still.
  double sinceHit = double.infinity;
}

/// The process entity's token: at most one barbarian holds the right to
/// telegraph at a time (L4 keeps the fight readable). Granted by
/// [coordinateAggro]; returned on recover/stagger/death with a cooldown
/// before the next grant.
final class AggroCoordinator {
  Entity? holder;
  double cooldown = 0;
}

/// A giant mid-transformation: added with `removeAfter:` so the
/// framework timer drives both the clip and the growth. While present
/// the barbarian holds still and swells from normal size to [giantScale].
final class Transforming {
  const Transforming();
}

/// Which pooled barbarian model this enemy borrowed. Released back to
/// the pool by an `onRemove` observer when the entity despawns, so waves
/// can keep reusing a small set of imported (un-cloneable) skinned models.
final class ModelSlot {
  const ModelSlot(this.index);
  final int index;
}

/// Marks a dying barbarian's death window. Added with `removeAfter:` so
/// the framework timer drives the effect: the death system maps
/// `expiryOf<Dissolving>` onto the sink-and-shrink progress.
final class Dissolving {
  const Dissolving();
}

/// The body's scene handles: the model wrapper node the death effect
/// sinks and shrinks (its base transform captured so a restart puts it
/// back), and — for the graybox capsule fallback only — its private
/// material (the emissive telegraph tell; imported models tell through
/// the highlight system).
final class BrawlerVisuals {
  BrawlerVisuals({required this.bodyRoot, this.capsuleMaterial})
    : _baseTransform = bodyRoot.localTransform.clone();

  /// The scaled model wrapper (character) or the capsule body node.
  final Node bodyRoot;
  final Matrix4 _baseTransform;
  final PhysicallyBasedMaterial? capsuleMaterial;

  /// The corpse's exit: it SINKS, at full size, until the ground has it.
  ///
  /// This used to shrink the body to nothing as well, which was a
  /// stand-in from before the ragdoll existed — a corpse shrivelling to a
  /// dot in front of you looks ridiculous, and it fights the ragdoll's
  /// whole point of being a body with weight. The sink alone reads as the
  /// ground taking it.
  ///
  /// [progress] runs 0 → 1 across the dissolve window; the body descends
  /// by [sink] over it, eased so it slips under rather than dropping.
  void applyDeath(double progress, double sink) {
    final eased = progress * progress;
    bodyRoot.localTransform =
        Matrix4.translation(Vector3(0, -sink * eased, 0)) * _baseTransform;
  }

  /// The giant's growth: [factor] 1 leaves the body at its (giant) base
  /// scale, so the transformation ramps from `1 / giantScale` up to 1.
  void applyGrowth(double factor) {
    bodyRoot.localTransform =
        _baseTransform * Matrix4.diagonal3(Vector3.all(factor));
  }

  void hide() => bodyRoot.visible = false;
}

/// The Rapier body handed to a corpse, kept so [settle] can nail it down
/// once it has come to rest.
final class Ragdoll {
  Ragdoll({required this.body});

  final RapierRigidBody body;

  /// Seconds since the corpse was handed to physics.
  double age = 0;

  bool settled = false;

  /// Nails the corpse down where it came to rest.
  ///
  /// These colliders carry no friction, so a body only ever slows by
  /// damping — asymptotically, never to zero. That residual crawl is the
  /// "dead enemies glide", and no damping value fixes it because the
  /// velocity never actually reaches zero. Turning the body FIXED does:
  /// it stops being simulated at all.
  void settle() {
    if (settled) return;
    settled = true;
    body
      ..linearVelocity = Vector3.zero()
      ..angularVelocity = Vector3.zero()
      ..type = BodyType.fixed;
  }
}
