part of '../player.dart';

enum PlayerLoco { idle, walk, run, strafeLeft, strafeRight, backpedal }

enum PlayerShot {
  slash,
  chop,
  sweepFinisher,
  heavy,
  rollForward,
  rollBack,
  rollLeft,
  rollRight,
  hit,
  fall,
  windCast,
  castShoot,
  castRaise,
  castBlock,
}

const List<PlayerShot> comboShots = [
  PlayerShot.slash,
  PlayerShot.chop,
  PlayerShot.sweepFinisher,
];

const Map<CastPose, PlayerShot> castShots = {
  CastPose.shoot: PlayerShot.castShoot,
  CastPose.raise: PlayerShot.castRaise,
  CastPose.block: PlayerShot.castBlock,
  CastPose.leap: PlayerShot.windCast,
};

final class CastClip {
  const CastClip(this.name, {required this.release});

  final String name;
  final double release;

  double scaleFor(CastMotion motion) => release / motion.release;
}

const Map<PlayerShot, CastClip> castClips = {
  PlayerShot.castShoot: CastClip('Ranged_Magic_Shoot', release: 0.09),
  PlayerShot.castRaise: CastClip('Ranged_Magic_Raise', release: 0.3),
  PlayerShot.castBlock: CastClip('Melee_Block', release: 0.18),
  PlayerShot.windCast: CastClip(
    'Jump_Full_Short',
    release: windCastClipSeconds,
  ),
};

final class SwingClip {
  const SwingClip(this.name, {required this.impact, this.from = 0});

  final String name;
  final double impact;
  final double from;

  double scaleFor(Swing swing) =>
      (impact - from) / (swing.startup + swing.active / 2);
}

const SwingClip slashClip = SwingClip('Melee_2H_Attack_Slice', impact: 0.4);
const SwingClip chopClip = SwingClip(
  'Melee_2H_Attack_Chop',
  impact: 0.81,
  from: 0.35,
);
const SwingClip sweepFinisherClip = SwingClip(
  'Melee_1H_Attack_Slice_Horizontal',
  impact: 0.26,
);
const SwingClip heavyClip = SwingClip(
  'Melee_2H_Attack_Spin',
  impact: 0.94,
  from: 0.12,
);

final class PlayerAnimator {
  PlayerAnimator({
    required this.locomotion,
    required this.shots,
    this.shotStarts = const {},
    this.blend,
  });

  final Map<PlayerLoco, AnimationClip> locomotion;
  final Map<PlayerShot, AnimationClip> shots;
  final Map<PlayerShot, double> shotStarts;
  final PoseBlend? blend;

  PlayerShot? active;
  PlayerLoco? _loco;
  int _swing = 0;
  final ClipHold _pause = ClipHold();

  bool hold(bool paused) =>
      _pause.hold(paused, shots.values.followedBy(locomotion.values));

  void update(Fighter fighter, PlayerMotion motion, double dt) {
    var desired = _desiredShot(fighter, motion);
    if (motion.downed) {
      desired = motion.airborne ? PlayerShot.fall : PlayerShot.hit;
    }
    final acting =
        fighter.swinging || fighter.phase.state == CombatPhase.casting;
    final freshSwing = fighter.swings != _swing && acting;
    _swing = fighter.swings;
    if (desired != active || freshSwing) _enterShot(desired, fighter);

    if (active != null) {
      _playShot(dt);
      return;
    }
    _playLocomotion(fighter, motion, dt);
  }

  PlayerShot? _desiredShot(Fighter fighter, PlayerMotion motion) {
    return switch (fighter.phase.state) {
      CombatPhase.startup || CombatPhase.active || CombatPhase.recovery =>
        fighter.heavy ? PlayerShot.heavy : comboShots[fighter.combo],
      CombatPhase.rolling => _isRoll(active) ? active : _rollShot(motion),
      CombatPhase.staggered => PlayerShot.hit,
      CombatPhase.casting => castShots[fighter.castMotion!.pose],
      CombatPhase.idle =>
        fighter.sinceHurt < flinchSeconds ? PlayerShot.hit : null,
    };
  }

  void _enterShot(PlayerShot? desired, Fighter fighter) {
    blend?.start(
      desired == PlayerShot.hit ? hitBlendSeconds : shotBlendSeconds,
    );
    _loco = null;
    active = desired;
    final clip = desired == null ? null : shots[desired];
    if (clip == null) return;
    final castClip = castClips[desired];
    final castMotion = fighter.castMotion;
    if (castClip != null && castMotion != null) {
      clip.playbackTimeScale = castClip.scaleFor(castMotion);
    }
    clip.gotoAndPlay(shotStarts[desired] ?? 0);
    if (desired != PlayerShot.hit) return;
    clip.weight = 1;
    for (final other in shots.values) {
      if (!identical(other, clip)) other.weight = 0;
    }
    for (final loop in locomotion.values) {
      loop.weight = 0;
    }
  }

  void _playShot(double dt) {
    final activeClip = shots[active]!;
    final fade = dt / oneShotFadeSeconds;
    for (final clip in shots.values) {
      final weight = identical(clip, activeClip) ? 1.0 : 0.0;
      clip.weight = moveToward(clip.weight, weight, fade);
    }
    for (final clip in locomotion.values) {
      clip.weight = moveToward(clip.weight, 0, fade);
    }
    _fillIdle();
  }

  void _playLocomotion(Fighter fighter, PlayerMotion motion, double dt) {
    final speed = motion.velocity.length;
    final target = _locomotionTarget(fighter, motion, speed);
    if (_loco != null && target != _loco) blend?.start(locomotionBlendSeconds);
    _loco = target;

    _stride(PlayerLoco.walk, speed, walkStrideSpeed);
    _stride(PlayerLoco.run, speed, runStrideSpeed);
    _stride(PlayerLoco.strafeLeft, speed, strafeStrideSpeed);
    _stride(PlayerLoco.strafeRight, speed, strafeStrideSpeed);
    _stride(PlayerLoco.backpedal, speed, backpedalStrideSpeed);

    final fade = dt / locomotionFadeSeconds;
    final tail = dt / oneShotFadeOutSeconds;
    for (final clip in shots.values) {
      clip.weight = moveToward(clip.weight, 0, tail);
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
      clip.weight = moveToward(clip.weight, targetWeight, fade);
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
    hold(false);
    active = null;
    _loco = null;
    _swing = 0;
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
  AnimationClip swing(SwingClip source, Swing swing) =>
      model.createAnimationClip(assets.clip(source.name))
        ..loop = false
        ..weight = 0
        ..playbackTimeScale = source.scaleFor(swing);

  final shots = <PlayerShot, AnimationClip>{
    PlayerShot.slash: swing(slashClip, lightCombo[0]),
    PlayerShot.chop: swing(chopClip, lightCombo[1]),
    PlayerShot.sweepFinisher: swing(sweepFinisherClip, lightCombo[2]),
    PlayerShot.heavy: swing(heavyClip, heavySwing),
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
    for (final MapEntry(key: shot, value: source) in castClips.entries)
      shot: model.createAnimationClip(assets.clip(source.name))
        ..loop = false
        ..weight = 0,
  };
  return PlayerAnimator(
    blend: PoseBlend.of(model),
    locomotion: locomotion,
    shots: shots,
    shotStarts: {
      for (final (shot, source) in [
        (PlayerShot.slash, slashClip),
        (PlayerShot.chop, chopClip),
        (PlayerShot.sweepFinisher, sweepFinisherClip),
        (PlayerShot.heavy, heavyClip),
      ])
        shot: source.from,
    },
  );
}
