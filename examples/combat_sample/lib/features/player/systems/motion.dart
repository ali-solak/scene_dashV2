part of '../player.dart';

/// Ground movement: stick-to-world mapping, the committed roll, and the
/// knockback arc.
void installPlayerMotion(GameBuilder game) {
  game.addSystem(
    Schedules.fixedUpdate,
    movePlayer,
    inSet: GameSets.movement,
    reads: const {Player, Fighter, Target},
    writes: const {PlayerMotion, SceneTransform, Knockback},
    runIf: inState(GameStatus.fighting),
  );
}

/// Updates player movement and facing.
void movePlayer(World world) {
  final axes = world.axes<MoveAxis>();
  final rig = world.resource<CameraRig>();
  final dt = world.dt;
  world
      .query3<Fighter, PlayerMotion, SceneTransform>(require: const [Player])
      .each((entity, fighter, motion, transform) {
        final (moveX, moveZ) = _stickWorldMove(axes, rig);
        final moving = moveX * moveX + moveZ * moveZ > 1e-6;

        if (moving) {
          motion.moveIntent
            ..setValues(moveX, 0, moveZ)
            ..normalize();
        }
        if (fighter.phase.justEntered(CombatPhase.rolling)) {
          _commitRollDirection(motion, moveX, moveZ, moving: moving);
        }

        _planarVelocity(
          world,
          entity,
          fighter,
          motion,
          transform,
          moveX,
          moveZ,
          dt,
        );
        _integrateMotion(world, entity, fighter, motion, transform, dt);
      });
}

/// Converts movement input into a clamped world-space vector.
(double, double) _stickWorldMove(AxisInput<MoveAxis> axes, CameraRig rig) {
  final inputX = axes.value(MoveAxis.x);
  final inputY = axes.value(MoveAxis.y);
  final sinYaw = math.sin(rig.yaw);
  final cosYaw = math.cos(rig.yaw);
  var moveX = cosYaw * inputX + sinYaw * inputY;
  var moveZ = -sinYaw * inputX + cosYaw * inputY;
  final magnitude = math.sqrt(moveX * moveX + moveZ * moveZ);
  if (magnitude > 1) {
    moveX /= magnitude;
    moveZ /= magnitude;
  }
  return (moveX, moveZ);
}

/// Chooses a roll direction on entry.
void _commitRollDirection(
  PlayerMotion motion,
  double moveX,
  double moveZ, {
  required bool moving,
}) {
  if (moving) {
    motion.rollDirection
      ..setValues(moveX, 0, moveZ)
      ..normalize();
  } else if (motion.moveIntent.length2 > 1e-6) {
    motion.rollDirection.setFrom(motion.moveIntent);
  } else {
    motion.rollDirection.setValues(
      math.sin(motion.facing),
      0,
      math.cos(motion.facing),
    );
  }
}

/// Writes the phase's ground-plane velocity.
void _planarVelocity(
  World world,
  Entity entity,
  Fighter fighter,
  PlayerMotion motion,
  SceneTransform transform,
  double moveX,
  double moveZ,
  double dt,
) {
  final velocity = motion.velocity..setZero();
  switch (fighter.phase.state) {
    case CombatPhase.idle:
      final locked = fighter.stance == Stance.locked;
      velocity.setValues(moveX, 0, moveZ);
      velocity.scale(locked ? lockedMoveSpeed : freeMoveSpeed);
      final targetTransform = locked ? _targetTransform(world, entity) : null;
      if (targetTransform != null) {
        final dx = targetTransform.translation.x - transform.translation.x;
        final dz = targetTransform.translation.z - transform.translation.z;
        motion.facing = math.atan2(dx, dz);
        // The back-off walk: moving away from the target is slower.
        if (dx * velocity.x + dz * velocity.z < 0) {
          velocity.scale(backpedalFactor);
        }
      } else if (velocity.length2 > 1e-9) {
        motion.facing = turnToward(
          motion.facing,
          math.atan2(velocity.x, velocity.z),
          turnRate * dt,
        );
      }
    case CombatPhase.rolling:
      velocity
        ..setFrom(motion.rollDirection)
        ..scale(rollSpeed);
    case CombatPhase.startup || CombatPhase.recovery:
      velocity.setValues(moveX, 0, moveZ);
      velocity.scale(
        (fighter.stance == Stance.locked ? lockedMoveSpeed : freeMoveSpeed) *
            attackMoveFactor,
      );
    case CombatPhase.active || CombatPhase.staggered:
      break;
  }
}

/// One step of world-space motion: the planar velocity while grounded,
/// the wind-cast leap's arc, the knockback's ballistic step, the launch
/// tumble (tips over once, lies flat through the downed beat), and the
/// final rotation write.
void _integrateMotion(
  World world,
  Entity entity,
  Fighter fighter,
  PlayerMotion motion,
  SceneTransform transform,
  double dt,
) {
  final knockback = world.tryGet<Knockback>(entity);
  // No steering while thrown or still on the floor from it.
  final grounded = knockback == null || !knockback.incapacitated;
  if (grounded) {
    transform.translation
      ..x += motion.velocity.x * dt
      ..z += motion.velocity.z * dt;
  }

  final sinceCast = fighter.sinceCast;
  if (sinceCast < windCastSeconds) {
    transform.translation.y =
        windCastJumpSpeed * sinceCast -
        0.5 * knockbackGravity * sinceCast * sinceCast;
  } else if (knockback != null) {
    knockback.step(dt, transform.translation);
  } else {
    transform.translation.y = 0;
  }
  clampToArena(transform.translation);

  if (knockback != null && knockback.incapacitated) {
    motion.tumble = towardProne(
      motion.tumble,
      dt,
      rate: knockback.airborne ? airborneProneRate : proneSettleRate,
    );
  } else {
    motion.tumble = 0;
  }
  // Copy knockback state for animation.
  motion.downed = knockback?.incapacitated ?? false;
  motion.airborne = knockback?.airborne ?? false; // falls vs lies
  transform.rotation.setAxisAngle(_up, motion.facing);
  if (motion.tumble != 0) {
    transform.rotation.setFrom(
      transform.rotation * Quaternion.axisAngle(_right, motion.tumble),
    );
  }
}

final Vector3 _up = Vector3(0, 1, 0);

/// The tumble axis: head-over-heels, not a flat spin.
final Vector3 _right = Vector3(1, 0, 0);
