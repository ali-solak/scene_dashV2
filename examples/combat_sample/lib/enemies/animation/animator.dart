part of '../enemies.dart';

/// The barbarian's animation mapper (task 15): the same shape as the
/// player's, on the brawl machine. Animations FOLLOW gameplay (L2): state
/// + velocity in, clip weights/times out; nothing here feeds combat.
enum BrawlerLoco { idle, walk, run, strafeLeft, strafeRight }

enum BrawlerShot { attack, hit, death, transform }

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
      case BrawlPhase.telegraph || BrawlPhase.swing || BrawlPhase.recover:
        // One clip spans the whole arc: the slow windup IS the telegraph,
        // the contact rides the swing window, the tail is the recover.
        desired = BrawlerShot.attack;
      case BrawlPhase.staggered:
        desired = BrawlerShot.hit;
      case BrawlPhase.dying:
        // Plays once and clamps at the last frame — the corpse — until the
        // delayed dissolve takes it (the "ragdoll then dissolve" staging).
        desired = BrawlerShot.death;
      case BrawlPhase.approach || BrawlPhase.circle:
        desired = null;
    }

    // STILL IN THE AIR (a wind blast). The stagger is far shorter than
    // the arc, so without this a thrown barbarian goes back to its walk
    // cycle while it is still metres up — jogging across the sky. Being
    // airborne outranks the phase; death still outranks both.
    // The DEATH clip, not the hit clip: it is the one that ends with the
    // body on the floor, which is what a thrown barbarian should look
    // like while it is down. It gets up again afterwards — the clip is
    // being borrowed for its pose, not its meaning.
    if (brawler.downed && phase != BrawlPhase.dying) {
      desired = BrawlerShot.death;
    }

    if (desired != active) {
      active = desired;
      final clip = desired == null ? null : shots[desired];
      if (clip != null) {
        clip.replay();
        if (desired == BrawlerShot.hit || desired == BrawlerShot.death) {
          // Stagger snaps (L2); death cuts hard under the hitstop.
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
      // The orbit tangent for circleDirection +1 is (-towardZ, towardX),
      // which is minus the facing's right vector — i.e. it strafes LEFT.
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

  /// Idle carries the residual so total clip weight never dips below 1 —
  /// otherwise a mid-crossfade dip flashes the bind pose (see the player
  /// animator's `_fillIdle`).
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
    BrawlerShot.attack: shot(
      'Melee_2H_Attack_Chop',
      chopClipSeconds,
      attackWindow,
    ),
    BrawlerShot.hit: shot('Hit_B', hitBClipSeconds, brawlStaggerSeconds),
    // The fall plays in real time; the corpse then lies through the
    // dissolve delay.
    BrawlerShot.death: shot('Death_B', deathBClipSeconds, deathBClipSeconds),
    // The giant's growth spurt, spanning exactly the transform window.
    BrawlerShot.transform: shot(
      'EXPERIMENTAL_Medium_Transform',
      transformClipSeconds,
      giantTransformSeconds,
    ),
  };
  return EnemyAnimator(locomotion: locomotion, shots: shots);
}
