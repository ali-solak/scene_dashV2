part of '../player.dart';

/// Startup: the player spawns as pure data — headless suites drive the
/// same path; the graybox body arrives in [attachPlayerVisuals].
void spawnPlayer(World world) {
  world.spawn(playerBundle());
}

/// OnEnter(fighting), scene-gated: give the player the Knight (clips bound
/// by node name, mapper attached) — or the graybox capsule when character
/// assets are absent. Deferred adds; found by tag (the spawn flushed
/// between startup and OnEnter).
void attachPlayerVisuals(World world) {
  final player = world.entitiesWith(require: const [Player]).firstOrNull;
  if (player == null) return;
  // Already bodied (a restart re-enters this state) — skip.
  if (world.tryGet<SceneNode>(player) != null) return;

  if (world.hasResource<CharacterAssets>()) {
    final assets = world.resource<CharacterAssets>();
    final model = assets.knight;
    // The sword rides the animated hand-slot joint.
    final sword = assets.sword;
    if (sword != null) {
      model.getChildByName('handslot.r')?.add(sword);
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
    if (sword != null) {
      // The ribbon hangs in WORLD space, not off the hand: it is a
      // record of where the blade has been, so it must not travel with
      // the fighter after the fact.
      final trail = SwordTrail.create();
      world.resource<Scene>().add(trail.node);
      world.add(player, BladeTrail(sword: sword, trail: trail));
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
      )..mesh = Mesh(
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

/// Resets the player to a clean, full-health idle at the spawn mark
/// (boot and every restart). Called by rules' `startRun` — the run owner
/// drives every feature's reset from one system, so they never collide.
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
    ..stance = Stance.free;
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

/// The i-frame ghost (task 19): while the roll's i-frame window is open,
/// the player glows a ghostly cyan rim (`Node.highlightColor`, the
/// engine's fresnel-style selection outline) so the invulnerability
/// reads. Materials/render follow gameplay (L3): the system sets the
/// color from `Fighter.iFramed`, the body never touches it. A deliberate
/// deviation from an authored ghost `.fmat` — the outline is the
/// lightweight read; swap in a fresnel `.fmat` if it wants more.
void updatePlayerGhost(World world) {
  final row =
      world.query2<Fighter, SceneNode>(require: const [Player]).firstOrNull;
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

/// The mapper system (task 15): render-side consumer of the fixed-step
/// gameplay state. Hitstop freezes the clips for free — the scene tick
/// receives the scaled delta.
void updatePlayerAnimation(World world) {
  final dt = world.dt;
  world
      .query3<Fighter, PlayerMotion, PlayerAnimator>(require: const [Player])
      .each((entity, fighter, motion, animator) {
    animator.update(fighter, motion, dt);
  });
}

/// Locomotion + stance (task 9), one fixed step at a time:
///
///  * free stance — camera-relative move, turn toward velocity;
///  * locked stance — strafe-set velocity facing the target, back-off walk
///    slower;
///  * rolling — the direction committed on entry, at roll speed;
///  * any other action phase — rooted, and never auto-turned.
void movePlayer(World world) {
  final axes = world.axes<MoveAxis>();
  final rig = world.resource<CameraRig>();
  final dt = world.dt;
  world
      .query3<Fighter, PlayerMotion, SceneTransform>(require: const [Player])
      .each((entity, fighter, motion, transform) {
    // Camera-relative input in world space: camera forward is
    // (sin yaw, 0, cos yaw), camera right (cos yaw, 0, -sin yaw).
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

    // Remember where the fighter is actually heading (survives the stick
    // being released before a buffered roll fires).
    if (magnitude > 1e-3) {
      motion.moveIntent
        ..setValues(moveX, 0, moveZ)
        ..normalize();
    }

    final phase = fighter.phase;
    if (phase.justEntered(CombatPhase.rolling)) {
      // Commit the roll direction once: this frame's input, else the last
      // heading the fighter had, else straight ahead.
      if (magnitude > 1e-3) {
        motion.rollDirection
          ..setValues(moveX, 0, moveZ)
          ..normalize();
      } else if (motion.moveIntent.length2 > 1e-6) {
        motion.rollDirection.setFrom(motion.moveIntent);
      } else {
        motion.rollDirection
            .setValues(math.sin(motion.facing), 0, math.cos(motion.facing));
      }
    }

    final velocity = motion.velocity..setZero();
    switch (phase.state) {
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
          motion.facing = _turnToward(
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
        // Committing, not frozen: you keep some drift through the windup
        // and the follow-through, so attacking never feels like a stop.
        velocity.setValues(moveX, 0, moveZ);
        velocity.scale(
          (fighter.stance == Stance.locked ? lockedMoveSpeed : freeMoveSpeed) *
              attackMoveFactor,
        );
      case CombatPhase.active || CombatPhase.staggered:
        break; // the active frames ARE the commitment; stagger is a loss
    }

    final knockback = world.tryGet<Knockback>(entity);
    // Airborne: the launch owns you — no steering mid-flight.
    // No steering while thrown OR while still on the floor from it.
    final grounded = knockback == null || !knockback.incapacitated;
    if (grounded) {
      transform.translation
        ..x += velocity.x * dt
        ..z += velocity.z * dt;
    }
    // The shove rides on top of (and through) any rooted action, and owns
    // the vertical arc.
    if (knockback != null) {
      knockback.step(dt, transform.translation);
    } else {
      transform.translation.y = 0;
    }
    clampToArena(transform.translation);

    // The launch tumble: a giant sends you head over heels, and the body
    // keeps spinning until it hits the dirt.
    if (knockback != null && knockback.airborne) {
      // Tips over once on the way down rather than spinning (see the
      // barbarians' movement for why).
      motion.tumble = _towardProne(motion.tumble, dt);
    } else if (knockback != null && knockback.downed > 0) {
      // Landed: flat on your back for the downed beat, like the corpses.
      motion.tumble = _towardProne(motion.tumble, dt);
    } else {
      motion.tumble = 0;
    }
    // The animator has no entity handle, so the floor beat rides here.
    motion.downed = knockback?.incapacitated ?? false;
    transform.rotation.setAxisAngle(_up, motion.facing);
    if (motion.tumble != 0) {
      transform.rotation.setFrom(
        transform.rotation * Quaternion.axisAngle(_right, motion.tumble),
      );
    }
  });
}

/// Kicks up earth on the frame a dodge commits (a no-op headless).
///
/// Off the machine's entry edge rather than off the input: a buffered
/// roll can fire a frame or two after the press, and the dirt belongs on
/// the frame the dodge actually started.
///
/// (The swing's crescent is the rules feature's — it is built from the
/// reach and arc of the hit check, which live there.)
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
      // The direction the dodge committed to, which is what the dirt
      // should be thrown away from.
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
  final row =
      world.query2<Fighter, BladeTrail>(require: const [Player]).firstOrNull;
  if (row == null) return;
  final (_, fighter, blade) = row;

  final swinging = switch (fighter.phase.state) {
    CombatPhase.active || CombatPhase.recovery => true,
    _ => false,
  };
  if (swinging) {
    blade.trail.sample(blade.sword.globalTransform);
  } else {
    blade.trail.retract();
  }
  blade.trail.rebuild(fighter.heavy ? heavyTrailTint : lightTrailTint);
}

/// Lock-on (task 10, press semantics per feel review). [LockPressed]
/// toggles: free = acquire the nearest living enemy within
/// [lockAcquireRange] and the view cone about the facing; locked =
/// release. [LockCycled] switches to the next candidate sorted by angle
/// around the player (wrapping). The lock also drops itself on target
/// death or a [lockBreakRange] break. [Fighter.stance] is derived here and
/// read everywhere else.
void lockOnSystem(World world) {
  final pressed = world.consumeAny<LockPressed>();
  final cycled = world.consumeAny<LockCycled>();
  final row = world
      .query3<Fighter, PlayerMotion, SceneTransform>(require: const [Player])
      .firstOrNull;
  if (row == null) return;
  final (player, fighter, _, transform) = row;
  final current = world.tryGet<Target>(player)?.entity;

  var held = current != null &&
          _isValidTarget(world, transform, current, lockBreakRange)
      ? current
      : null;

  if (pressed) {
    if (held != null) {
      held = null; // toggle off
    } else {
      // One rule, no cone gate: prefer whatever is in front of the camera
      // (within the half-plane), nearest first; behind-the-camera targets
      // only when nothing is in front. A press always locks something in
      // range; a press while locked always releases.
      final cameraYaw = world.resource<CameraRig>().yaw;
      _Candidate? bestInView;
      _Candidate? bestBehind;
      for (final candidate in _lockCandidates(world, transform)) {
        final inView =
            _angleDifference(candidate.angle, cameraYaw).abs() <= math.pi / 2;
        if (inView) {
          if (bestInView == null || candidate.distance < bestInView.distance) {
            bestInView = candidate;
          }
        } else if (bestBehind == null ||
            candidate.distance < bestBehind.distance) {
          bestBehind = candidate;
        }
      }
      held = (bestInView ?? bestBehind)?.entity;
    }
  } else if (cycled && held != null) {
    final currentTarget = held;
    final others = _lockCandidates(world, transform)
        .where((c) => c.entity != currentTarget)
        .toList()
      ..sort((a, b) => a.angle.compareTo(b.angle));
    if (others.isNotEmpty) {
      final currentAngle = _angleTo(transform, world, currentTarget);
      held = others
          .firstWhere(
            (c) => c.angle > currentAngle,
            orElse: () => others.first, // wrap around
          )
          .entity;
    }
  }

  if (held == null) {
    if (current != null) world.remove<Target>(player);
  } else if (held != current) {
    world.add(player, Target(held)); // re-add replaces
  }
  fighter.stance = held != null ? Stance.locked : Stance.free;
}

/// Follows the fight (update schedule, writes the [CameraRig] the
/// `cameraBuilder` in `main` reads) with a souls orbit: the camera rides a
/// yaw/pitch sphere around the fighter's chest, position-smoothed so it
/// trails motion instead of snapping. Free = pointer-owned yaw and pitch
/// (mouse hover/drag, touch swipe); locked = yaw steered from the player
/// toward the target, pitch eased to its combat elevation, focus slid
/// toward the pair's midpoint so both fighters stay framed.
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

  if (targetTransform != null) {
    // The lock owns the framing; manual look is discarded, not banked.
    look.takeYawDelta();
    look.takePitchDelta();
    final desiredYaw = math.atan2(
      targetTransform.translation.x - position.x,
      targetTransform.translation.z - position.z,
    );
    final yawBlend = 1 - math.exp(-cameraYawSharpness * dt);
    rig.yaw += _angleDifference(desiredYaw, rig.yaw) * yawBlend;
    final pitchBlend = 1 - math.exp(-cameraPitchSharpness * dt);
    rig.pitch += (cameraLockedPitch - rig.pitch) * pitchBlend;
  } else {
    rig.yaw += look.takeYawDelta() * lookYawSensitivity;
    rig.pitch = (rig.pitch + look.takePitchDelta() * lookPitchSensitivity)
        .clamp(cameraPitchMin, cameraPitchMax);
  }

  rig.target.setValues(
    position.x,
    position.y + cameraFocusHeight,
    position.z,
  );
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

  // The orbit point on the yaw/pitch sphere around the FOCUS, chased with
  // its own smoothing so movement reads as the camera trailing the run.
  //
  // Around the focus, not around the player. Orbiting the player while
  // merely LOOKING at a point biased toward the target framed neither
  // fighter: the camera sat behind the player at a fixed distance and the
  // enemy fell wherever it fell — usually off the top of the screen once
  // it was more than a few metres out.
  //
  // Locked, the distance also grows with how far apart the two are, so
  // the pair stays in frame instead of the camera holding a fixed leash
  // and letting the target walk out of it.
  var distance = cameraDistance;
  if (targetTransform != null) {
    final dx = targetTransform.translation.x - position.x;
    final dz = targetTransform.translation.z - position.z;
    final separation = math.sqrt(dx * dx + dz * dz);
    distance = (cameraDistance + separation * lockedDistanceGain)
        .clamp(cameraDistance, maxLockedCameraDistance);
  }
  final horizontal = distance * math.cos(rig.pitch);
  final desiredX = rig.target.x - math.sin(rig.yaw) * horizontal;
  // rig.target.y already carries cameraFocusHeight.
  final desiredY = rig.target.y + distance * math.sin(rig.pitch) + rig.kick;
  final desiredZ = rig.target.z - math.cos(rig.yaw) * horizontal;
  final positionBlend = 1 - math.exp(-cameraPositionSharpness * dt);
  rig.position.setValues(
    rig.position.x + (desiredX - rig.position.x) * positionBlend,
    rig.position.y + (desiredY - rig.position.y) * positionBlend,
    rig.position.z + (desiredZ - rig.position.z) * positionBlend,
  );
}

/// Outlines via `Node.highlightColor` (set on every mesh-bearing node —
/// the engine reads it per mesh component): gold for the locked enemy, and
/// a rising orange telegraph pulse that overrides it — the readability
/// tell works on any body, imported meshes included, without cloning
/// materials per enemy (L3: one system owns the color).
void updateEnemyHighlights(World world) {
  final player = world.entitiesWith(require: const [Player]).firstOrNull;
  final locked = player == null ? null : world.tryGet<Target>(player)?.entity;
  world.query2<Brawler, SceneNode>(require: const [Enemy]).each((
    enemy,
    brawler,
    ref,
  ) {
    Vector4? color;
    if (brawler.phase.state == BrawlPhase.telegraph) {
      final tell =
          (brawler.phase.elapsed / telegraphSeconds).clamp(0.0, 1.0);
      color = Vector4(1.0, 0.45 - 0.25 * tell, 0.1, 0.35 + 0.65 * tell);
    } else if (enemy == locked) {
      color = Vector4(1.0, 0.78, 0.25, 1.0);
    }
    _setHighlight(ref.node, color);
  });
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

/// Eases a thrown fighter down onto their back on landing.
double _towardProne(double tumble, double dt) {
  const prone = math.pi / 2;
  final step = proneSettleRate * dt;
  if ((prone - tumble).abs() <= step) return prone;
  return tumble + (prone - tumble).sign * step;
}

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

/// Signed shortest difference `a - b`, wrapped to `(-pi, pi]`.
double _angleDifference(double a, double b) {
  var difference = (a - b) % (2 * math.pi);
  if (difference > math.pi) difference -= 2 * math.pi;
  if (difference < -math.pi) difference += 2 * math.pi;
  return difference;
}

/// Turns [from] toward [to] by at most [maxDelta] radians, shortest arc.
double _turnToward(double from, double to, double maxDelta) {
  final difference = _angleDifference(to, from);
  if (difference.abs() <= maxDelta) return to;
  return from + difference.sign * maxDelta;
}
