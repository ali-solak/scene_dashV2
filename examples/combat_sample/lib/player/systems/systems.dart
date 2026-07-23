part of '../player.dart';

/// Startup: the player spawns as pure data, so headless suites drive the
/// same path; the body arrives in [attachPlayerVisuals].
void spawnPlayer(World world) {
  world.spawn(playerBundle());
}

/// Per frame, scene-gated: give the player the Knight (clips bound by
/// node name), or the graybox capsule when character assets are absent.
/// Skips anyone already bodied. Runs from the title screen on, so the
/// fighter is in the clearing before the run begins.
void attachPlayerVisuals(World world) {
  final player = world.entitiesWith(require: const [Player]).firstOrNull;
  if (player == null) return;
  // Already bodied (a restart re-enters this state); skip.
  if (world.tryGet<SceneNode>(player) != null) return;

  if (world.hasResource<CharacterAssets>()) {
    final assets = world.resource<CharacterAssets>();
    final model = assets.knight;
    // The two-handed sword rides the animated hand-slot joint. Cloned so a
    // restart's re-body never re-parents the shared template.
    final weapon = assets.sword?.clone();
    if (weapon != null) {
      model.getChildByName('handslot.r')?.add(weapon);
    }
    final wrapper = Node(
      name: 'player-model',
      localTransform: Matrix4.compose(
        Vector3.zero(),
        Quaternion.axisAngle(Vector3(0, 1, 0), characterModelYaw),
        Vector3.all(characterScale),
      ),
    )..add(model);
    world.add(player, SceneNode(Node(name: 'player')..add(wrapper)));
    world.add(player, buildPlayerAnimator(assets, model));
    if (weapon != null) {
      // The ribbon hangs in world space, not off the hand: it records
      // where the blade has been, so it must not travel with the fighter.
      final trail = SwordTrail.create();
      world.resource<Scene>().add(trail.node);
      world.add(player, BladeTrail(weapon: weapon, trail: trail));
    }
    return;
  }

  final material = PhysicallyBasedMaterial()
    ..baseColorFactor = Vector4(0.16, 0.42, 0.85, 1)
    ..roughnessFactor = 0.6;
  final root = Node(name: 'player')
    ..add(
      Node(
          localTransform: Matrix4.translation(
            Vector3(0, playerCapsuleHeight / 2 + playerCapsuleRadius, 0),
          ),
        )
        ..mesh = Mesh(
          CapsuleGeometry(
            radius: playerCapsuleRadius,
            height: playerCapsuleHeight,
          ),
          material,
        ),
    )
    ..add(
      Node(
        localTransform: Matrix4.translation(
          Vector3(0, 1.35, playerCapsuleRadius + 0.1),
        ),
      )..mesh = Mesh(CuboidGeometry(Vector3(0.14, 0.14, 0.3)), material),
    );
  world.add(player, SceneNode(root));
}

/// Leaving the fight (menu, death) wipes buffered intents: a roll pressed
/// on the way out must not fire on the way back in. The widget-side gate
/// stops NEW combat input off the fighting screen; this clears what was
/// already banked inside the wall-clock press window.
void clearCombatIntents(World world) {
  world.buffer<CombatAction>().clear();
}

/// Resets the player to a clean, full-health idle at the spawn mark.
/// `OnEnter(fighting)` behind [freshRun]: boot, title start and restart —
/// never a menu-close resume.
void resetPlayerRun(World world) {
  final row = world
      .query3<Fighter, PlayerMotion, Health>(require: const [Player])
      .firstOrNull;
  if (row == null) return;
  final (player, fighter, motion, health) = row;
  health.current = health.max;
  fighter.phase.go(CombatPhase.idle);
  fighter
    ..heavy = false
    ..stance = Stance.free
    ..sinceHurt = double.infinity;
  motion
    ..facing = math.pi
    ..velocity.setZero();
  motion.rollDirection.setValues(0, 0, 1);
  motion.moveIntent.setZero();
  world.remove<Target>(player);
  world.tryGet<Knockback>(player)?.clear();
  world
      .tryGet<SceneTransform>(player)
      ?.translation
      .setValues(playerSpawnX, 0, playerSpawnZ);
  world.tryGet<PlayerAnimator>(player)?.reset();
}

/// The i-frame ghost: while the roll's i-frame window is open the player
/// glows a cyan rim (`Node.highlightColor`) so the invulnerability reads.
/// The system sets the color from `Fighter.iFramed`; the body never
/// touches it (L3).
void updatePlayerGhost(World world) {
  final row = world
      .query2<Fighter, SceneNode>(require: const [Player])
      .firstOrNull;
  if (row == null) return;
  final (entity, fighter, ref) = row;
  // Two ways to be untouchable: the roll's i-frames, and the arc a
  // giant's blow throws you through. Both wear the same ghost.
  final launched = world.tryGet<Knockback>(entity)?.incapacitated ?? false;
  _setHighlight(
    ref.node,
    fighter.iFramed || launched ? Vector4(0.45, 0.9, 1.0, 0.9) : null,
  );
}

/// The mapper system: render-side consumer of the fixed-step gameplay
/// state. Hitstop freezes the clips for free; the scene tick receives the
/// scaled delta.
void updatePlayerAnimation(World world) {
  final dt = world.dt;
  world
      .query3<Fighter, PlayerMotion, PlayerAnimator>(require: const [Player])
      .each((entity, fighter, motion, animator) {
        animator.update(fighter, motion, dt);
      });
}

/// Locomotion + stance, one fixed step at a time:
///
///  * free stance: camera-relative move, turn toward velocity;
///  * locked stance: strafe-set velocity facing the target, slower back-off;
///  * rolling: the direction committed on entry, at roll speed;
///  * any other action phase: rooted, and never auto-turned.
void movePlayer(World world) {
  final axes = world.axes<MoveAxis>();
  final rig = world.resource<CameraRig>();
  final dt = world.dt;
  world
      .query3<Fighter, PlayerMotion, SceneTransform>(require: const [Player])
      .each((entity, fighter, motion, transform) {
        final (moveX, moveZ) = _stickWorldMove(axes, rig);
        final moving = moveX * moveX + moveZ * moveZ > 1e-6;

        // Remember where the fighter is actually heading (survives the stick
        // being released before a buffered roll fires).
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

/// The stick in world space, clamped to unit length. Camera forward is
/// (sin yaw, 0, cos yaw), camera right (cos yaw, 0, -sin yaw).
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

/// Commit the roll direction once, on entry: this frame's input, else the
/// last heading the fighter had, else straight ahead.
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

/// The phase's ground-plane velocity, written into [motion.velocity]:
/// idle steers (locked strafe with the slower back-off, free turns toward
/// the heading); rolling rides the committed direction; startup/recovery
/// keep a drift so attacking never feels like a stop; active and
/// staggered are rooted (the active frames ARE the commitment).
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
    motion.tumble = towardProne(motion.tumble, dt, rate: proneSettleRate);
  } else {
    motion.tumble = 0;
  }
  // The animator has no entity handle, so the floor beat rides here.
  motion.downed = knockback?.incapacitated ?? false;
  motion.airborne = knockback?.airborne ?? false; // falls vs lies
  transform.rotation.setAxisAngle(_up, motion.facing);
  if (motion.tumble != 0) {
    transform.rotation.setFrom(
      transform.rotation * Quaternion.axisAngle(_right, motion.tumble),
    );
  }
}

/// Kicks up earth on the frame a dodge commits (a no-op headless).
/// Off the machine's entry edge, not the input: a buffered roll can fire
/// a frame or two after the press. (The swing's crescent lives in the
/// rules feature, built from the hit check's reach and arc.)
void spawnPlayerFx(World world) {
  final row = world
      .query3<Fighter, PlayerMotion, SceneTransform>(require: const [Player])
      .firstOrNull;
  if (row == null) return;
  final (_, fighter, motion, transform) = row;

  if (fighter.phase.justEntered(CombatPhase.rolling)) {
    spawnDashDust(
      world,
      transform.translation.clone(),
      // dirt is thrown away from the committed dodge direction.
      motion.rollDirection.clone(),
    );
  }
}

/// Feeds the blade ribbon (a no-op headless).
///
/// Samples while the swing is live and RETRACTS the rest of the time, so
/// the trail draws itself on during the cut and pulls back in after,
/// instead of popping in and out.
void updateBladeTrail(World world) {
  final row = world
      .query2<Fighter, BladeTrail>(require: const [Player])
      .firstOrNull;
  if (row == null) return;
  final (_, fighter, blade) = row;

  final swinging = switch (fighter.phase.state) {
    CombatPhase.active || CombatPhase.recovery => true,
    _ => false,
  };
  if (swinging) {
    blade.trail.sample(blade.weapon.globalTransform);
  } else {
    blade.trail.retract();
  }
  blade.trail.rebuild(fighter.heavy ? heavyTrailTint : lightTrailTint);
}

/// Lock-on. [LockPressed] toggles: acquire the nearest living enemy in
/// [lockAcquireRange], or release. [LockCycled] steps to the next
/// candidate by angle (wrapping). The lock drops itself on target death
/// or a [lockBreakRange] break. [Fighter.stance] is derived here and read
/// everywhere else.
void lockOnSystem(World world) {
  final pressed = world.consumeAny<LockPressed>();
  final cycled = world.consumeAny<LockCycled>();
  final row = world
      .query3<Fighter, PlayerMotion, SceneTransform>(require: const [Player])
      .firstOrNull;
  if (row == null) return;
  final (player, fighter, _, transform) = row;
  final current = world.tryGet<Target>(player)?.entity;

  var held =
      current != null &&
          _isValidTarget(world, transform, current, lockBreakRange)
      ? current
      : null;

  if (pressed) {
    held = held != null
        ? null // toggle off
        : _acquireTarget(world, transform);
  } else if (cycled && held != null) {
    held = _nextTarget(world, transform, held);
  }

  if (held == null) {
    if (current != null) world.remove<Target>(player);
  } else if (held != current) {
    world.add(player, Target(held)); // re-add replaces
  }
  fighter.stance = held != null ? Stance.locked : Stance.free;
}

/// Acquire on press: the nearest living enemy in range, preferring those
/// in front of the camera; behind-camera only when nothing is in front.
/// No cone gate — a press always locks something in range.
Entity? _acquireTarget(World world, SceneTransform player) {
  final cameraYaw = world.resource<CameraRig>().yaw;
  _Candidate? bestInView;
  _Candidate? bestBehind;
  for (final candidate in _lockCandidates(world, player)) {
    final inView =
        angleDifference(candidate.angle, cameraYaw).abs() <= math.pi / 2;
    if (inView) {
      if (bestInView == null || candidate.distance < bestInView.distance) {
        bestInView = candidate;
      }
    } else if (bestBehind == null || candidate.distance < bestBehind.distance) {
      bestBehind = candidate;
    }
  }
  return (bestInView ?? bestBehind)?.entity;
}

/// Cycle (Q): the next candidate clockwise by angle, wrapping; [current]
/// keeps the lock when it is the only candidate left.
Entity _nextTarget(World world, SceneTransform player, Entity current) {
  final others =
      _lockCandidates(world, player).where((c) => c.entity != current).toList()
        ..sort((a, b) => a.angle.compareTo(b.angle));
  if (others.isEmpty) return current;
  final currentAngle = _angleTo(player, world, current);
  return others
      .firstWhere(
        (c) => c.angle > currentAngle,
        orElse: () => others.first, // wrap around
      )
      .entity;
}

/// Follows the fight (writes the [CameraRig] that `cameraBuilder` in
/// `main` reads) with a souls orbit: a yaw/pitch sphere around the
/// fighter's chest, position-smoothed. Free = pointer-owned yaw and
/// pitch; locked = yaw steered toward the target, focus slid toward the
/// pair's midpoint so both fighters stay framed.
void updateCameraRig(World world) {
  final rig = world.resource<CameraRig>();
  final look = world.resource<LookInput>();
  final row = world
      .query2<PlayerMotion, SceneTransform>(require: const [Player])
      .firstOrNull;
  if (row == null) return;
  final (player, motion, transform) = row;
  final targetTransform = _targetTransform(world, player);
  final position = transform.translation;
  final dt = world.dt;

  // The title shot: a wide, slow orbit of the clearing. It frames the
  // place, not the fighter; the push-in at run start introduces him.
  if (world.state<GameStatus>() == GameStatus.title) {
    rig
      ..yaw += titleOrbitRate * dt
      ..pitch = titleCameraPitch;
    rig.target.setValues(0, cameraFocusHeight, 0);
    final horizontal = titleCameraDistance * math.cos(rig.pitch);
    rig.position.setValues(
      rig.target.x - math.sin(rig.yaw) * horizontal,
      rig.target.y + titleCameraDistance * math.sin(rig.pitch),
      rig.target.z - math.cos(rig.yaw) * horizontal,
    );
    return;
  }

  if (targetTransform != null) {
    // The lock owns the framing; manual look is discarded, not banked.
    look.takeYawDelta();
    look.takePitchDelta();
    final desiredYaw = math.atan2(
      targetTransform.translation.x - position.x,
      targetTransform.translation.z - position.z,
    );
    final yawBlend = 1 - math.exp(-cameraYawSharpness * dt);
    rig.yaw += angleDifference(desiredYaw, rig.yaw) * yawBlend;
    final pitchBlend = 1 - math.exp(-cameraPitchSharpness * dt);
    rig.pitch += (cameraLockedPitch - rig.pitch) * pitchBlend;
  } else {
    rig.yaw += look.takeYawDelta() * lookYawSensitivity;
    rig.pitch = (rig.pitch + look.takePitchDelta() * lookPitchSensitivity)
        .clamp(cameraPitchMin, cameraPitchMax);
  }

  rig.target.setValues(position.x, position.y + cameraFocusHeight, position.z);
  if (targetTransform != null) {
    rig.target.setValues(
      position.x +
          (targetTransform.translation.x - position.x) * lockedCameraBias,
      position.y + cameraFocusHeight,
      position.z +
          (targetTransform.translation.z - position.z) * lockedCameraBias,
    );
  }

  // Heavy connects punch the camera up briefly; the impulse decays fast.
  rig.kick *= math.exp(-cameraKickDecay * dt);

  // Orbit around the focus, not the player: orbiting the player while
  // merely looking toward the target framed neither fighter. Locked, the
  // distance also grows with separation so the pair stays in frame.
  var distance = cameraDistance;
  if (targetTransform != null) {
    final dx = targetTransform.translation.x - position.x;
    final dz = targetTransform.translation.z - position.z;
    final separation = math.sqrt(dx * dx + dz * dz);
    distance = (cameraDistance + separation * lockedDistanceGain).clamp(
      cameraDistance,
      maxLockedCameraDistance,
    );
  }
  final horizontal = distance * math.cos(rig.pitch);
  final desiredX = rig.target.x - math.sin(rig.yaw) * horizontal;
  // rig.target.y already carries cameraFocusHeight.
  final desiredY = rig.target.y + distance * math.sin(rig.pitch) + rig.kick;
  final desiredZ = rig.target.z - math.cos(rig.yaw) * horizontal;
  // The opening push-in rides the existing smoothing: same desired
  // framing from the first frame, only the rate differs during the intro.
  var sharpness = cameraPositionSharpness;
  if (rig.intro > 0) {
    rig.intro = math.max(0, rig.intro - dt);
    sharpness = introCameraSharpness;
  }
  final positionBlend = 1 - math.exp(-sharpness * dt);
  rig.position.setValues(
    rig.position.x + (desiredX - rig.position.x) * positionBlend,
    rig.position.y + (desiredY - rig.position.y) * positionBlend,
    rig.position.z + (desiredZ - rig.position.z) * positionBlend,
  );
}

/// Outlines via `Node.highlightColor` (set on every mesh-bearing node):
/// gold for the locked enemy, a rising orange telegraph pulse overriding
/// it. Works on any body without cloning materials per enemy (L3: one
/// system owns the color).
///
/// The recursive node walk is the expensive part, so steady states (no
/// highlight, the static lock gold) write once and are remembered in
/// [EnemyHighlights]; only a telegraph's rising pulse rewrites per frame.
void updateEnemyHighlights(World world) {
  final player = world.entitiesWith(require: const [Player]).firstOrNull;
  final locked = player == null ? null : world.tryGet<Target>(player)?.entity;
  final applied = world.resource<EnemyHighlights>().applied;
  world.query2<Brawler, SceneNode>(require: const [Enemy]).each((
    enemy,
    brawler,
    ref,
  ) {
    if (brawler.phase.state == BrawlPhase.telegraph) {
      final tell = (brawler.phase.elapsed / telegraphSeconds).clamp(0.0, 1.0);
      applied[enemy.index] = EnemyHighlights.telegraph;
      _setHighlight(
        ref.node,
        Vector4(1.0, 0.45 - 0.25 * tell, 0.1, 0.35 + 0.65 * tell),
      );
      return;
    }
    final state = enemy == locked
        ? EnemyHighlights.locked
        : EnemyHighlights.none;
    if (applied[enemy.index] == state) return;
    applied[enemy.index] = state;
    _setHighlight(
      ref.node,
      state == EnemyHighlights.locked ? Vector4(1.0, 0.78, 0.25, 1.0) : null,
    );
  });
}

/// Last highlight state written per enemy, by entity index. Slot reuse is
/// safe: a fresh enemy's nodes start unhighlighted, which IS the `none`
/// state, so a stale `none` skipping the first write is correct and any
/// other stale value mismatches and rewrites. Owned by the player
/// feature: enemies never read their own outline.
final class EnemyHighlights {
  static const int none = 0;
  static const int locked = 1;
  static const int telegraph = 2;

  final Map<int, int> applied = <int, int>{};
}

void _setHighlight(Node node, Vector4? color) {
  node.highlightColor = color;
  for (final child in node.children) {
    _setHighlight(child, color);
  }
}

// --- Helpers ---

final Vector3 _up = Vector3(0, 1, 0);

/// The tumble axis: head-over-heels, not a flat spin.
final Vector3 _right = Vector3(1, 0, 0);

final class _Candidate {
  const _Candidate(this.entity, this.distance, this.angle);
  final Entity entity;
  final double distance;
  final double angle;
}

List<_Candidate> _lockCandidates(World world, SceneTransform player) {
  final candidates = <_Candidate>[];
  world.query2<Health, SceneTransform>(require: const [Enemy]).each((
    enemy,
    health,
    enemyTransform,
  ) {
    if (!health.alive) return;
    final dx = enemyTransform.translation.x - player.translation.x;
    final dz = enemyTransform.translation.z - player.translation.z;
    final distance = math.sqrt(dx * dx + dz * dz);
    if (distance > lockAcquireRange) return;
    candidates.add(_Candidate(enemy, distance, math.atan2(dx, dz)));
  });
  return candidates;
}

bool _isValidTarget(
  World world,
  SceneTransform player,
  Entity target,
  double range,
) {
  final health = world.tryGet<Health>(target);
  if (health == null || !health.alive) return false;
  final transform = world.tryGet<SceneTransform>(target);
  if (transform == null) return false;
  final dx = transform.translation.x - player.translation.x;
  final dz = transform.translation.z - player.translation.z;
  return dx * dx + dz * dz <= range * range;
}

SceneTransform? _targetTransform(World world, Entity player) {
  final target = world.tryGet<Target>(player);
  return target == null ? null : world.tryGet<SceneTransform>(target.entity);
}

double _angleTo(SceneTransform player, World world, Entity entity) {
  final transform = world.tryGet<SceneTransform>(entity);
  if (transform == null) return 0;
  return math.atan2(
    transform.translation.x - player.translation.x,
    transform.translation.z - player.translation.z,
  );
}
