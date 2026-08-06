part of '../player.dart';

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

  /// Plays a visual recoil without changing combat state.
  void playBackwardDash() {
    _backwardDashRemaining = rollClipSeconds / rollPlaybackScale;
  }

  void update(Fighter fighter, PlayerMotion motion, double dt) {
    final recoiling = _backwardDashRemaining > 0;
    _backwardDashRemaining = math.max(0.0, _backwardDashRemaining - dt);

    var desired = _desiredShot(fighter, motion);
    if (recoiling && fighter.phase.state != CombatPhase.rolling) {
      desired = PlayerShot.rollBack;
    }
    if (motion.downed) {
      desired = motion.airborne ? PlayerShot.fall : PlayerShot.hit;
    }
    if (desired != active) _enterShot(desired, fighter);

    if (active != null) {
      _playShot(fighter, dt);
      return;
    }
    _playLocomotion(fighter, motion, dt);
  }

  PlayerShot? _desiredShot(Fighter fighter, PlayerMotion motion) {
    return switch (fighter.phase.state) {
      CombatPhase.startup || CombatPhase.active || CombatPhase.recovery =>
        fighter.heavy ? PlayerShot.heavy : PlayerShot.strike,
      CombatPhase.rolling => _isRoll(active) ? active : _rollShot(motion),
      CombatPhase.staggered => PlayerShot.hit,
      CombatPhase.idle =>
        fighter.sinceCast < windCastSeconds
            ? PlayerShot.windCast
            : fighter.sinceHurt < flinchSeconds
            ? PlayerShot.hit
            : null,
    };
  }

  void _enterShot(PlayerShot? desired, Fighter fighter) {
    final promoted =
        active == PlayerShot.strike &&
        desired == PlayerShot.heavy &&
        fighter.phase.state == CombatPhase.startup;
    active = desired;
    final clip = desired == null ? null : shots[desired];
    if (clip == null) return;
    if (promoted) {
      clip.gotoAndPlay(fighter.phase.elapsed * clip.playbackTimeScale);
    } else {
      clip.replay();
    }
    if (desired != PlayerShot.hit) return;
    clip.weight = 1;
    for (final other in shots.values) {
      if (!identical(other, clip)) other.weight = 0;
    }
    for (final loop in locomotion.values) {
      loop.weight = 0;
    }
  }

  void _playShot(Fighter fighter, double dt) {
    final activeClip = shots[active]!;
    if (fighter.phase.state == CombatPhase.startup) {
      final startup = fighter.heavy ? heavyStartupSeconds : startupSeconds;
      final windupEnd = startup * activeClip.playbackTimeScale;
      if (activeClip.playbackTime > windupEnd) activeClip.seek(windupEnd);
    }
    final fade = dt / oneShotFadeSeconds;
    for (final clip in shots.values) {
      final weight = identical(clip, activeClip) ? 1.0 : 0.0;
      clip.weight = _approach(clip.weight, weight, fade);
    }
    for (final clip in locomotion.values) {
      clip.weight = _approach(clip.weight, 0, fade);
    }
    _fillIdle();
  }

  void _playLocomotion(Fighter fighter, PlayerMotion motion, double dt) {
    final speed = motion.velocity.length;
    final target = _locomotionTarget(fighter, motion, speed);

    _stride(PlayerLoco.walk, speed, walkStrideSpeed);
    _stride(PlayerLoco.run, speed, runStrideSpeed);
    _stride(PlayerLoco.strafeLeft, speed, strafeStrideSpeed);
    _stride(PlayerLoco.strafeRight, speed, strafeStrideSpeed);
    _stride(PlayerLoco.backpedal, speed, backpedalStrideSpeed);

    final fade = dt / locomotionFadeSeconds;
    final tail = dt / oneShotFadeOutSeconds;
    for (final clip in shots.values) {
      clip.weight = _approach(clip.weight, 0, tail);
    }
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

  PlayerLoco _locomotionTarget(
    Fighter fighter,
    PlayerMotion motion,
    double speed,
  ) {
    if (speed < 0.05) return PlayerLoco.idle;
    if (fighter.stance == Stance.free) {
      return speed >= runBlendSpeed ? PlayerLoco.run : PlayerLoco.walk;
    }
    final sinFacing = math.sin(motion.facing);
    final cosFacing = math.cos(motion.facing);
    final forward =
        (motion.velocity.x * sinFacing + motion.velocity.z * cosFacing) / speed;
    final side =
        (motion.velocity.x * cosFacing - motion.velocity.z * sinFacing) / speed;
    return forward.abs() >= side.abs()
        ? (forward >= 0 ? PlayerLoco.walk : PlayerLoco.backpedal)
        : (side >= 0 ? PlayerLoco.strafeRight : PlayerLoco.strafeLeft);
  }

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

/// Creates animation clips bound to [model].
PlayerAnimator buildPlayerAnimator(CharacterAssets assets, Node model) {
  AnimationClip loop(String name) =>
      model.createAnimationClip(assets.clip(name))
        ..loop = true
        ..weight = 0
        ..play();
  AnimationClip shot(String name, double clipSeconds, double windowSeconds) =>
      model.createAnimationClip(assets.clip(name))
        ..loop = false
        ..weight = 0
        ..playbackTimeScale = math.min(
          maxOneShotPlaybackScale,
          clipSeconds / windowSeconds,
        );

  final locomotion = <PlayerLoco, AnimationClip>{
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
    // The asset pack has dodge clips but no roll.
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
    // Loop the airborne pose to avoid returning to the bind pose.
    PlayerShot.fall: loop('Jump_Idle'),
    PlayerShot.windCast: shot(
      'Jump_Full_Short',
      windCastClipSeconds,
      windCastSeconds,
    ),
  };
  return PlayerAnimator(locomotion: locomotion, shots: shots);
}
