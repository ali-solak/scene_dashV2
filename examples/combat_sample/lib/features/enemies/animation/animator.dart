part of '../enemies.dart';

/// The barbarian's animation mapper: brawl state + velocity in, clip
/// weights/times out. Animations follow gameplay; nothing here feeds
/// combat.
enum BrawlerLoco { idle, walk, run, strafeLeft, strafeRight }

enum BrawlerShot { rise, taunt, attack, hit, death, fall, dodge, transform }

final class EnemyAnimator {
  EnemyAnimator({required this.locomotion, required this.shots});

  final Map<BrawlerLoco, AnimationClip> locomotion;
  final Map<BrawlerShot, AnimationClip> shots;

  BrawlerShot? active;

  /// Last chop the mapper replayed for; see the combo note in [update].
  int _lastChop = -1;
  bool frozen = false;

  void update(Brawler brawler, double dt, {bool transforming = false}) {
    if (frozen) return;
    // The growth spurt overrides everything: the giant is busy swelling.
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

  /// The pose the brawl state asks for, or null to fall through to
  /// locomotion.
  BrawlerShot? _pickShot(Brawler brawler, BrawlPhase phase) {
    // Airborne (a wind blast) outranks the phase; death outranks both. The
    // stagger is far shorter than the arc, so without this a thrown
    // barbarian would jog its walk cycle across the sky.
    if (brawler.downed && phase != BrawlPhase.dying) {
      return brawler.airborne ? BrawlerShot.fall : BrawlerShot.death;
    }
    return switch (phase) {
      BrawlPhase.rising => BrawlerShot.rise,
      BrawlPhase.taunting => BrawlerShot.taunt,
      // One clip spans the whole arc: the slow windup IS the telegraph,
      // the contact rides the swing window, the tail is the recover.
      BrawlPhase.telegraph ||
      BrawlPhase.swing ||
      BrawlPhase.recover => BrawlerShot.attack,
      BrawlPhase.dodging => BrawlerShot.dodge,
      BrawlPhase.staggered || BrawlPhase.dying => BrawlerShot.hit,
      // The fire/lava flinch: a non-staggering tick still jolts the body,
      // but only while walking or circling; a barbarian mid-swing swings
      // through the burn, exactly as the player does (poise).
      BrawlPhase.approach || BrawlPhase.circle =>
        brawler.sinceHurt < brawlerFlinchSeconds ? BrawlerShot.hit : null,
    };
  }

  /// The hit pose serves both the stagger and, while dying, the corpse's
  /// shorter hit window.
  void _rateHitClip(BrawlPhase phase) {
    shots[BrawlerShot.hit]!.playbackTimeScale =
        hitBClipSeconds /
        (phase == BrawlPhase.dying ? corpseHitSeconds : brawlStaggerSeconds);
  }

  /// Switches pose. The listed one-shots snap to full weight: a real
  /// crossfade on this rig's mirrored bones lerps negative scale through
  /// zero and flattens the model (flutter_scene #249), so the sample never
  /// blends between poses. The rise snaps so its prone first frame is not
  /// preceded by a stand.
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

  /// A combo's follow-up chop re-enters `telegraph` without the pose ever
  /// leaving `attack`, so the phase alone cannot trigger a replay: the
  /// chop counter does. Rescaled per chop, since a combo's opener and its
  /// follow-up wind up at different speeds.
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

  /// Weights the active one-shot in and everything else out.
  void _playShot(double dt) {
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
  }

  /// The idle/walk/run/strafe blend, each clip's playback tied to ground
  /// speed so strides match the distance covered.
  void _playLocomotion(Brawler brawler, BrawlPhase phase, double dt) {
    final speed = brawler.velocity.length;
    final BrawlerLoco target;
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

  /// Restart resurrection: back to a clean idle.
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

  /// Holds the final hit pose while Rapier tumbles the whole body.
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

    BrawlerShot.death: shot('Death_B', deathBClipSeconds, deathBClipSeconds),

    BrawlerShot.fall: loop('Jump_Idle'),
    // The roll goes mostly backward (see [dodgeBackWeight]), so the
    // backward clip is the one that matches the travel; the left/right
    // pair read as strafing on the spot. One clip, not one per side: the
    // player registers clips by animation name, so a second instance of
    // the same name would evict the first.
    BrawlerShot.dodge: shot('Dodge_Backward', dodgeClipSeconds, dodgeSeconds),

    // The giant's growth spurt, spanning exactly the transform window.
    BrawlerShot.transform: shot(
      'EXPERIMENTAL_Medium_Transform',
      transformClipSeconds,
      giantTransformSeconds,
    ),
  };
  return EnemyAnimator(locomotion: locomotion, shots: shots);
}
