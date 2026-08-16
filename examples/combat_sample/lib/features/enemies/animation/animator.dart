part of '../enemies.dart';

enum BrawlerLoco { idle, walk, run, strafeLeft, strafeRight }

enum BrawlerShot { rise, taunt, attack, hit, death, fall, dodge, transform }

final class EnemyAnimator {
  EnemyAnimator({required this.locomotion, required this.shots});

  final Map<BrawlerLoco, AnimationClip> locomotion;
  final Map<BrawlerShot, AnimationClip> shots;

  BrawlerShot? active;

  int _lastChop = -1;
  bool frozen = false;

  void update(Brawler brawler, double dt, {bool transforming = false}) {
    if (frozen) return;
    if (transforming) {
      if (active != BrawlerShot.transform) _enterShot(BrawlerShot.transform);
      _playShot(dt);
      return;
    }
    final phase = brawler.phase.state;
    _rateHitClip(phase);

    final desired = _pickShot(brawler, phase);
    if (desired != active) _enterShot(desired);
    _replayOnNewChop(brawler);

    if (active != null) {
      _playShot(dt);
      return;
    }
    _playLocomotion(brawler, phase, dt);
  }

  BrawlerShot? _pickShot(Brawler brawler, BrawlPhase phase) {
    // Airborne poses override every living phase.
    if (brawler.downed && phase != BrawlPhase.dying) {
      return brawler.airborne ? BrawlerShot.fall : BrawlerShot.death;
    }
    return switch (phase) {
      BrawlPhase.rising => BrawlerShot.rise,
      BrawlPhase.taunting => BrawlerShot.taunt,
      // One clip spans windup, swing, and recovery.
      BrawlPhase.telegraph ||
      BrawlPhase.swing ||
      BrawlPhase.recover => BrawlerShot.attack,
      BrawlPhase.dodging => BrawlerShot.dodge,
      BrawlPhase.staggered || BrawlPhase.dying => BrawlerShot.hit,
      BrawlPhase.approach || BrawlPhase.circle =>
        brawler.sinceHurt < brawlerFlinchSeconds ? BrawlerShot.hit : null,
    };
  }

  void _rateHitClip(BrawlPhase phase) {
    shots[BrawlerShot.hit]!.playbackTimeScale =
        hitBClipSeconds /
        (phase == BrawlPhase.dying ? corpseHitSeconds : brawlStaggerSeconds);
  }

  void _enterShot(BrawlerShot? desired) {
    active = desired;
    final clip = desired == null ? null : shots[desired];
    if (clip == null) return;
    clip.replay();
    if (desired != BrawlerShot.hit &&
        desired != BrawlerShot.death &&
        desired != BrawlerShot.rise) {
      return;
    }
    clip.weight = 1;
    for (final other in shots.values) {
      if (!identical(other, clip)) other.weight = 0;
    }
    for (final loop in locomotion.values) {
      loop.weight = 0;
    }
  }

  void _replayOnNewChop(Brawler brawler) {
    if (active != BrawlerShot.attack || _lastChop == brawler.chopIndex) return;
    _lastChop = brawler.chopIndex;
    shots[BrawlerShot.attack]!
      ..playbackTimeScale =
          chopClipSeconds *
          brawler.tempo /
          (brawler.windup + swingSeconds + recoverSeconds)
      ..replay();
  }

  void _playShot(double dt) {
    final fade = dt / brawlerOneShotFadeSeconds;
    final activeClip = shots[active]!;
    for (final clip in shots.values) {
      clip.weight = moveToward(
        clip.weight,
        identical(clip, activeClip) ? 1 : 0,
        fade,
      );
    }
    for (final clip in locomotion.values) {
      clip.weight = moveToward(clip.weight, 0, fade);
    }
    _fillIdle();
  }

  void _playLocomotion(Brawler brawler, BrawlPhase phase, double dt) {
    final speed = brawler.velocity.length;
    final BrawlerLoco target;
    if (speed < 0.05) {
      target = BrawlerLoco.idle;
    } else if (phase == BrawlPhase.circle && !brawler.hasToken) {
      // Positive orbit direction strafes left.
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
      clip.weight = moveToward(clip.weight, 0, fade);
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
      clip.weight = moveToward(clip.weight, targetWeight, fade);
    });
    _fillIdle();
  }

  // Keep total animation weight at one.
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

  void reset() {
    frozen = false;
    active = null;
    _lastChop = -1;
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

  /// Freezes the corpse pose during tumble.
  void freeze() {
    frozen = true;
    for (final clip in shots.values) {
      clip.pause();
    }
    for (final clip in locomotion.values) {
      clip.pause();
    }
  }

  void _stride(BrawlerLoco key, double speed, double strideSpeed) {
    locomotion[key]!.playbackTimeScale = (speed / strideSpeed)
        .clamp(0.5, 1.8)
        .toDouble();
  }
}

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
    BrawlerShot.death: shot('Death_B', deathBClipSeconds, deathBClipSeconds),
    BrawlerShot.fall: loop('Jump_Idle'),
    BrawlerShot.dodge: shot('Dodge_Backward', dodgeClipSeconds, dodgeSeconds),
    BrawlerShot.transform: shot(
      'EXPERIMENTAL_Medium_Transform',
      transformClipSeconds,
      giantTransformSeconds,
    ),
  };
  return EnemyAnimator(locomotion: locomotion, shots: shots);
}
