part of '../player.dart';

/// The player's animation mapper: looping locomotion clips blended by
/// weight, one-shots fired from machine-phase changes. Animation follows
/// gameplay (L2); no timing here feeds back into combat.
enum PlayerLoco { idle, walk, run, strafeLeft, strafeRight, backpedal }

enum PlayerShot {
  strike,
  heavy,
  rollForward,
  rollBack,
  rollLeft,
  rollRight,
  hit,
  fall,
  windCast,
}

final class PlayerAnimator {
  PlayerAnimator({required this.locomotion, required this.shots});

  final Map<PlayerLoco, AnimationClip> locomotion;
  final Map<PlayerShot, AnimationClip> shots;

  PlayerShot? active;
  double _backwardDashRemaining = 0;

  /// Plays the existing backward dodge as a visual-only recoil. Gameplay
  /// remains in its current phase, so this grants neither roll movement nor
  /// i-frames.
  void playBackwardDash() {
    _backwardDashRemaining = rollClipSeconds / rollPlaybackScale;
  }

  /// Drives the clips from the frame's gameplay state. Phase-to-shot
  /// mapping derives from state, not machine edges: this runs on the
  /// update schedule, and a multi-fixed-step frame can skip an edge.
  void update(Fighter fighter, PlayerMotion motion, double dt) {
    final phase = fighter.phase.state;
    final recoiling = _backwardDashRemaining > 0;
    _backwardDashRemaining = math.max(0.0, _backwardDashRemaining - dt);

    PlayerShot? desired;
    switch (phase) {
      case CombatPhase.startup || CombatPhase.active || CombatPhase.recovery:
        desired = fighter.heavy ? PlayerShot.heavy : PlayerShot.strike;
      case CombatPhase.rolling:
        // Committed once per roll: keep the direction picked on entry.
        desired = _isRoll(active) ? active : _rollShot(motion);
      case CombatPhase.staggered:
        desired = PlayerShot.hit;
      case CombatPhase.idle:
        // The cast leap and the flinch live in the idle arm alone, so
        // they stay visual: swing through either and the swing wins, as
        // poise promises. The leap outranks the flinch.
        if (fighter.sinceCast < windCastSeconds) {
          desired = PlayerShot.windCast;
        } else {
          desired = fighter.sinceHurt < flinchSeconds ? PlayerShot.hit : null;
        }
    }

    if (recoiling && phase != CombatPhase.rolling) {
      desired = PlayerShot.rollBack;
    }

    // Thrown outranks the phase: the stagger ends while the body is still
    // metres up, and without this the fighter would run on air. Holds
    // through the landing beat too; fall pose airborne, hit pose down.
    if (motion.downed) {
      desired = motion.airborne ? PlayerShot.fall : PlayerShot.hit;
    }

    if (desired != active) {
      final promoted =
          active == PlayerShot.strike &&
          desired == PlayerShot.heavy &&
          phase == CombatPhase.startup;
      active = desired;
      final clip = desired == null ? null : shots[desired];
      if (clip != null) {
        if (promoted) {
          // Mid-windup promotion continues the raise instead of visibly
          // restarting the swing from frame zero.
          clip.gotoAndPlay(fighter.phase.elapsed * clip.playbackTimeScale);
        } else {
          clip.replay();
        }
        if (desired == PlayerShot.hit) {
          // Stagger snaps; no ease-in (L2).
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
      final activeClip = shots[active]!;
      // A held button delays the swing past the clip's windup: hold the
      // clip at its windup pose until the machine goes active, otherwise
      // the visual contact plays before the hit exists.
      if (phase == CombatPhase.startup) {
        final windupEnd =
            (fighter.heavy ? heavyStartupSeconds : startupSeconds) *
            activeClip.playbackTimeScale;
        if (activeClip.playbackTime > windupEnd) activeClip.seek(windupEnd);
      }
      final fade = dt / oneShotFadeSeconds;
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

    // Locomotion blend from speed + stance.
    final speed = motion.velocity.length;
    PlayerLoco target;
    if (speed < 0.05) {
      target = PlayerLoco.idle;
    } else if (fighter.stance == Stance.free) {
      target = speed >= runBlendSpeed ? PlayerLoco.run : PlayerLoco.walk;
    } else {
      // Strafe set: dominant direction of the velocity in the facing frame.
      final forwardX = math.sin(motion.facing);
      final forwardZ = math.cos(motion.facing);
      final forward =
          (motion.velocity.x * forwardX + motion.velocity.z * forwardZ) / speed;
      final side =
          (motion.velocity.x * forwardZ - motion.velocity.z * forwardX) / speed;
      // `side` is dot(velocity, right) where right = (cos f, -sin f), so
      // positive is the fighter's right; map it straight.
      target = forward.abs() >= side.abs()
          ? (forward >= 0 ? PlayerLoco.walk : PlayerLoco.backpedal)
          : (side >= 0 ? PlayerLoco.strafeRight : PlayerLoco.strafeLeft);
    }

    // Feet follow the ground: stride playback scales with actual speed.
    _stride(PlayerLoco.walk, speed, walkStrideSpeed);
    _stride(PlayerLoco.run, speed, runStrideSpeed);
    _stride(PlayerLoco.strafeLeft, speed, strafeStrideSpeed);
    _stride(PlayerLoco.strafeRight, speed, strafeStrideSpeed);
    _stride(PlayerLoco.backpedal, speed, backpedalStrideSpeed);

    final fade = dt / locomotionFadeSeconds;
    // The swing's tail rides out on its own fade so the follow-through is
    // never cut mid-clip. Fading in stays a hard snap (see
    // `oneShotFadeSeconds`): an attack must start on the frame you press.
    final tail = dt / oneShotFadeOutSeconds;
    for (final clip in shots.values) {
      clip.weight = _approach(clip.weight, 0, tail);
    }
    // A gait restart (seek 0) only from a true standstill: restarting on
    // every direction change froze the model into a first-frame cutout.
    final fromStandstill = locomotion[PlayerLoco.idle]!.weight > 0.9;
    locomotion.forEach((key, clip) {
      final targetWeight = key == target ? 1.0 : 0.0;
      if (fromStandstill &&
          key != PlayerLoco.idle &&
          clip.weight <= 1e-3 &&
          targetWeight > 0) {
        clip.seek(0);
      }
      clip.weight = _approach(clip.weight, targetWeight, fade);
    });
    _fillIdle();
  }

  /// Guards against the bind-pose ("T-pose") flash: the AnimationPlayer
  /// only normalizes weights down, so a weight sum below 1 shows the rig
  /// snapping to bind for a beat. Idle carries the residual so the total
  /// is always at least 1.
  void _fillIdle() {
    var sum = 0.0;
    for (final clip in shots.values) {
      sum += clip.weight;
    }
    for (final entry in locomotion.entries) {
      if (entry.key != PlayerLoco.idle) sum += entry.value.weight;
    }
    final floor = (1 - sum).clamp(0.0, 1.0).toDouble();
    final idle = locomotion[PlayerLoco.idle]!;
    if (idle.weight < floor) idle.weight = floor;
  }

  /// Restart: back to a clean idle.
  void reset() {
    active = null;
    _backwardDashRemaining = 0;
    for (final clip in shots.values) {
      clip.stop();
      clip.weight = 0;
    }
    for (final entry in locomotion.entries) {
      entry.value.weight = entry.key == PlayerLoco.idle ? 1 : 0;
    }
  }

  void _stride(PlayerLoco key, double speed, double strideSpeed) {
    locomotion[key]!.playbackTimeScale = (speed / strideSpeed)
        .clamp(0.5, 1.8)
        .toDouble();
  }

  PlayerShot _rollShot(PlayerMotion motion) {
    final forwardX = math.sin(motion.facing);
    final forwardZ = math.cos(motion.facing);
    final forward =
        motion.rollDirection.x * forwardX + motion.rollDirection.z * forwardZ;
    final side =
        motion.rollDirection.x * forwardZ - motion.rollDirection.z * forwardX;
    // Same frame as the locomotion pick: positive `side` is the fighter's
    // right, so the right-hand dodge plays when the roll goes right.
    return forward.abs() >= side.abs()
        ? (forward >= 0 ? PlayerShot.rollForward : PlayerShot.rollBack)
        : (side >= 0 ? PlayerShot.rollRight : PlayerShot.rollLeft);
  }

  static bool _isRoll(PlayerShot? shot) =>
      shot == PlayerShot.rollForward ||
      shot == PlayerShot.rollBack ||
      shot == PlayerShot.rollLeft ||
      shot == PlayerShot.rollRight;

  static double _approach(double value, double target, double step) {
    if ((target - value).abs() <= step) return target;
    return value + (target - value).sign * step;
  }
}

/// Instantiates the knight's clips against [model] (channels bind by node
/// name) with playback scaled so each one-shot spans its machine window.
PlayerAnimator buildPlayerAnimator(CharacterAssets assets, Node model) {
  AnimationClip loop(String name) =>
      model.createAnimationClip(assets.clip(name))
        ..loop = true
        ..weight = 0
        ..play();
  // Windows in combat.dart are sized so clip/window lands at or under
  // `maxOneShotPlaybackScale`: a swing plays slightly brisk and finishes.
  // If a clip is swapped for a longer one, its window must grow with it.
  AnimationClip shot(String name, double clipSeconds, double windowSeconds) =>
      model.createAnimationClip(assets.clip(name))
        ..loop = false
        ..weight = 0
        ..playbackTimeScale = math.min(
          maxOneShotPlaybackScale,
          clipSeconds / windowSeconds,
        );

  final locomotion = <PlayerLoco, AnimationClip>{
    // Two-handed guard: the axe is up, ready; reads as a fighter.
    PlayerLoco.idle: loop('Melee_2H_Idle')..weight = 1,
    PlayerLoco.walk: loop('Walking_A'),
    PlayerLoco.run: loop('Running_A'),
    PlayerLoco.strafeLeft: loop('Running_Strafe_Left'),
    PlayerLoco.strafeRight: loop('Running_Strafe_Right'),
    PlayerLoco.backpedal: loop('Walking_Backwards'),
  };
  const lightWindow = startupSeconds + activeSeconds + recoverySeconds;
  const heavyWindow =
      heavyStartupSeconds + heavyActiveSeconds + heavyRecoverySeconds;
  final shots = <PlayerShot, AnimationClip>{
    // Normal is a quick horizontal slice; heavy is the big spin sweep.
    // Both cover the same wide strike arc.
    PlayerShot.strike: shot(
      'Melee_2H_Attack_Slice',
      strikeClipSeconds,
      lightWindow,
    ),
    PlayerShot.heavy: shot(
      'Melee_2H_Attack_Spin',
      heavyClipSeconds,
      heavyWindow,
    ),
    // The packs ship no true roll; the dodges are it. Played snappy (not
    // stretched over the window, which read as a slide): the hop lands
    // early and the landing pose rides out the i-frame tail.
    PlayerShot.rollForward: shot(
      'Dodge_Forward',
      rollClipSeconds,
      rollClipSeconds / rollPlaybackScale,
    ),
    PlayerShot.rollBack: shot(
      'Dodge_Backward',
      rollClipSeconds,
      rollClipSeconds / rollPlaybackScale,
    ),
    PlayerShot.rollLeft: shot(
      'Dodge_Left',
      rollClipSeconds,
      rollClipSeconds / rollPlaybackScale,
    ),
    PlayerShot.rollRight: shot(
      'Dodge_Right',
      rollClipSeconds,
      rollClipSeconds / rollPlaybackScale,
    ),
    PlayerShot.hit: shot('Hit_A', hitClipSeconds, staggerSeconds),
    // The mid-air hang while a launch carries the fighter. Loops: a
    // launch can outlast the clip, and a finished one-shot drops to the
    // bind pose (a T-pose in the air).
    PlayerShot.fall: loop('Jump_Idle'),
    // The leap that throws the wind gust: a full jump, played brisk so it
    // reads as a quick hop.
    PlayerShot.windCast: shot(
      'Jump_Full_Short',
      windCastClipSeconds,
      windCastSeconds,
    ),
  };
  return PlayerAnimator(locomotion: locomotion, shots: shots);
}
