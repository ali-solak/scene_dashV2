part of '../enemies.dart';

/// The barbarian's animation mapper: brawl state + velocity in, clip
/// weights/times out. Animations follow gameplay; nothing here feeds
/// combat.
enum BrawlerLoco { idle, walk, run, strafeLeft, strafeRight }

enum BrawlerShot { rise, taunt, attack, hit, death, fall, transform }

final class EnemyAnimator {
  EnemyAnimator({required this.locomotion, required this.shots});

  final Map<BrawlerLoco, AnimationClip> locomotion;
  final Map<BrawlerShot, AnimationClip> shots;

  BrawlerShot? active;

  /// Set when the corpse is handed to the ragdoll: the skeleton holds its
  /// last pose and physics owns the body's orientation.
  bool frozen = false;

  /// Stops every clip where it stands (the ragdoll takes over).
  void freeze() {
    frozen = true;
    for (final clip in shots.values) {
      clip.pause();
    }
    for (final clip in locomotion.values) {
      clip.pause();
    }
  }

  void update(Brawler brawler, double dt, {bool transforming = false}) {
    if (frozen) return;
    final phase = brawler.phase.state;

    BrawlerShot? desired;
    // The transformation overrides everything: the giant is busy growing.
    if (transforming) {
      final clip = shots[BrawlerShot.transform]!;
      if (active != BrawlerShot.transform) {
        active = BrawlerShot.transform;
        clip.replay();
      }
      final fade = dt / brawlerOneShotFadeSeconds;
      for (final other in shots.values) {
        other.weight = _approach(
          other.weight,
          identical(other, clip) ? 1 : 0,
          fade,
        );
      }
      for (final loop in locomotion.values) {
        loop.weight = _approach(loop.weight, 0, fade);
      }
      _fillIdle();
      return;
    }
    switch (phase) {
      case BrawlPhase.rising:
        // Climbing out of the floor; snapped on so frame one is already
        // prone (see the snap set below), not the standing idle sinking.
        desired = BrawlerShot.rise;
      case BrawlPhase.taunting:
        desired = BrawlerShot.taunt;
      case BrawlPhase.telegraph || BrawlPhase.swing || BrawlPhase.recover:
        // One clip spans the whole arc: the slow windup IS the telegraph,
        // the contact rides the swing window, the tail is the recover.
        desired = BrawlerShot.attack;
      case BrawlPhase.staggered:
        desired = BrawlerShot.hit;
      case BrawlPhase.dying:
        // Plays once and clamps at the last frame (the corpse) until the
        // delayed dissolve takes it.
        desired = BrawlerShot.death;
      case BrawlPhase.approach || BrawlPhase.circle:
        // The fire/lava flinch: a non-staggering tick still jolts the body,
        // but only while walking or circling; a barbarian mid-swing swings
        // through the burn, exactly as the player does (poise).
        desired = brawler.sinceHurt < brawlerFlinchSeconds
            ? BrawlerShot.hit
            : null;
    }

    // Airborne (a wind blast) outranks the phase; death outranks both.
    // The stagger is far shorter than the arc, so without this a thrown
    // barbarian would jog its walk cycle across the sky.
    if (brawler.downed && phase != BrawlPhase.dying) {
      desired = brawler.airborne ? BrawlerShot.fall : BrawlerShot.death;
    }

    if (desired != active) {
      active = desired;
      final clip = desired == null ? null : shots[desired];
      if (clip != null) {
        clip.replay();
        if (desired == BrawlerShot.hit ||
            desired == BrawlerShot.death ||
            desired == BrawlerShot.rise) {
          // Stagger and death snap hard; the rise snaps so its prone first
          // frame is not preceded by a stand.
          clip.weight = 1;
          for (final other in shots.values) {
            if (!identical(other, clip)) other.weight = 0;
          }
          for (final loop in locomotion.values) {
            loop.weight = 0;
          }
        }
      }
    }

    if (active != null) {
      final fade = dt / brawlerOneShotFadeSeconds;
      final activeClip = shots[active]!;
      for (final clip in shots.values) {
        clip.weight = _approach(
          clip.weight,
          identical(clip, activeClip) ? 1 : 0,
          fade,
        );
      }
      for (final clip in locomotion.values) {
        clip.weight = _approach(clip.weight, 0, fade);
      }
      _fillIdle();
      return;
    }

    final speed = brawler.velocity.length;
    BrawlerLoco target;
    if (speed < 0.05) {
      target = BrawlerLoco.idle;
    } else if (phase == BrawlPhase.circle && !brawler.hasToken) {
      // The orbit tangent for circleDirection +1 is (-towardZ, towardX):
      // minus the facing's right vector, so it strafes left.
      target = brawler.circleDirection >= 0
          ? BrawlerLoco.strafeLeft
          : BrawlerLoco.strafeRight;
    } else {
      target = speed >= brawlerRunBlendSpeed
          ? BrawlerLoco.run
          : BrawlerLoco.walk;
    }

    _stride(BrawlerLoco.walk, speed, brawlerWalkStrideSpeed);
    _stride(BrawlerLoco.run, speed, brawlerRunStrideSpeed);
    _stride(BrawlerLoco.strafeLeft, speed, brawlerStrafeStrideSpeed);
    _stride(BrawlerLoco.strafeRight, speed, brawlerStrafeStrideSpeed);

    final fade = dt / brawlerLocomotionFadeSeconds;
    for (final clip in shots.values) {
      clip.weight = _approach(clip.weight, 0, fade);
    }
    final fromStandstill = locomotion[BrawlerLoco.idle]!.weight > 0.9;
    locomotion.forEach((key, clip) {
      final targetWeight = key == target ? 1.0 : 0.0;
      if (fromStandstill &&
          key != BrawlerLoco.idle &&
          clip.weight <= 1e-3 &&
          targetWeight > 0) {
        clip.seek(0);
      }
      clip.weight = _approach(clip.weight, targetWeight, fade);
    });
    _fillIdle();
  }

  /// Idle carries the residual so total clip weight never dips below 1;
  /// a mid-crossfade dip would flash the bind pose.
  void _fillIdle() {
    var sum = 0.0;
    for (final clip in shots.values) {
      sum += clip.weight;
    }
    for (final entry in locomotion.entries) {
      if (entry.key != BrawlerLoco.idle) sum += entry.value.weight;
    }
    final floor = (1 - sum).clamp(0.0, 1.0).toDouble();
    final idle = locomotion[BrawlerLoco.idle]!;
    if (idle.weight < floor) idle.weight = floor;
  }

  /// Restart resurrection: back to a clean idle, unfrozen.
  void reset() {
    frozen = false;
    active = null;
    for (final clip in shots.values) {
      clip.stop();
      clip.weight = 0;
    }
    for (final entry in locomotion.entries) {
      entry.value
        ..weight = entry.key == BrawlerLoco.idle ? 1 : 0
        ..play();
    }
  }

  void _stride(BrawlerLoco key, double speed, double strideSpeed) {
    locomotion[key]!.playbackTimeScale = (speed / strideSpeed)
        .clamp(0.5, 1.8)
        .toDouble();
  }

  static double _approach(double value, double target, double step) {
    if ((target - value).abs() <= step) return target;
    return value + (target - value).sign * step;
  }
}

/// Instantiates the barbarian's clips against its cloned [model].
EnemyAnimator buildEnemyAnimator(CharacterAssets assets, Node model) {
  AnimationClip loop(String name) =>
      model.createAnimationClip(assets.clip(name))
        ..loop = true
        ..weight = 0
        ..play();
  AnimationClip shot(String name, double clipSeconds, double windowSeconds) =>
      model.createAnimationClip(assets.clip(name))
        ..loop = false
        ..weight = 0
        ..playbackTimeScale = clipSeconds / windowSeconds;

  final locomotion = <BrawlerLoco, AnimationClip>{
    BrawlerLoco.idle: loop('Melee_2H_Idle')..weight = 1,
    BrawlerLoco.walk: loop('Walking_B'),
    BrawlerLoco.run: loop('Running_B'),
    BrawlerLoco.strafeLeft: loop('Running_Strafe_Left'),
    BrawlerLoco.strafeRight: loop('Running_Strafe_Right'),
  };
  const attackWindow = telegraphSeconds + swingSeconds + recoverSeconds;
  final shots = <BrawlerShot, AnimationClip>{
    // Climbs out of the ground on spawn; taunts between orbits mid-fight.
    BrawlerShot.rise: shot(
      'Skeletons_Awaken_Floor',
      awakenClipSeconds,
      risingSeconds,
    ),
    BrawlerShot.taunt: shot('Skeletons_Taunt', tauntClipSeconds, tauntSeconds),
    BrawlerShot.attack: shot(
      'Melee_2H_Attack_Chop',
      chopClipSeconds,
      attackWindow,
    ),
    BrawlerShot.hit: shot('Hit_B', hitBClipSeconds, brawlStaggerSeconds),
    // A barbarian collapse, not the skeleton death: this body falls in one
    // piece. Plays in real time; the corpse then lies through the dissolve
    // delay.
    BrawlerShot.death: shot('Death_B', deathBClipSeconds, deathBClipSeconds),
    // The mid-air hang while a wind blast carries the body. Loops: a
    // one-shot would finish mid-flight and drop the body to its bind pose.
    BrawlerShot.fall: loop('Jump_Idle'),
    // The giant's growth spurt, spanning exactly the transform window.
    BrawlerShot.transform: shot(
      'EXPERIMENTAL_Medium_Transform',
      transformClipSeconds,
      giantTransformSeconds,
    ),
  };
  return EnemyAnimator(locomotion: locomotion, shots: shots);
}
