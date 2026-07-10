part of '../player.dart';

/// Startup: build and spawn the player. Gated on the scene at
/// registration (`runIf: hasResource<Scene>()`) — the body and feedback
/// nodes need the scene's shader resources.
void spawnPlayer(World world) {
  world.spawn(playerBundle());
}

/// OnEnter(playing): give the player a fresh [PlayerKnockback] — attached
/// rather than bundled so a re-add replaces it and every run starts
/// unshoved (the old knockback.reset() died here). Headless boots have no
/// player and simply skip.
void attachPlayerKnockback(World world) {
  final player = world
      .entitiesWith(require: const [Player])
      .firstWhere((entity) => true);
  if (player == null) return;
  world.add(player, PlayerKnockback());
}

/// Translates input into a move-and-slide request each fixed step.
void movePlayer(World world) {
  final input = world.buttons<GameAction>();
  final dt = world.dt;
  world.query2<PlayerKnockback, SceneNode>(require: const [Player]).each((
    entity,
    knockback,
    ref,
  ) {
    final controller = ref.component<RapierKinematicCharacterController>();
    if (controller == null) return;

    final node = ref.node;
    _snapToRamp(node, knockback);

    // Read translation from the matrix storage — getTranslation() allocates.
    final m = node.localTransform.storage;
    final positionY = m[13];
    // Ordering keeps the original mapping: left = +1, right = -1.
    final horizontal = input.axis(GameAction.right, GameAction.left);
    final motion = knockback.step(dt)..x += horizontal * playerStrafeSpeed * dt;
    final nextX = m[12] + motion.x;
    final nextZ = m[14] + motion.z;
    if (isOverRampFootprint(nextX, nextZ)) {
      motion.y = playerGroundYAtZ(nextZ) - positionY;
      knockback.ground();
    } else {
      motion.y += knockback.fallStep(dt);
    }
    controller.move(motion);
  });
}

void _snapToRamp(Node node, PlayerKnockback knockback) {
  final transform = node.localTransform;
  final m = transform.storage;
  if (!isOverRampFootprint(m[12], m[14])) return;
  m[13] = playerGroundYAtZ(m[14]);
  // Reassign to trip the transform dirty flag after the in-place edit.
  node.localTransform = transform;
  knockback.ground();
}

/// Unfolds the six visual crab legs, then layers a procedural two-group
/// gait on top while the player strafes. Only player-owned child nodes
/// move.
void animateCrabLegs(World world) {
  final input = world.buttons<GameAction>();
  final dt = world.dt;
  world.query<PlayerVisuals>(require: const [Player]).each((entity, v) {
    v.legExtension01 = approach(
      v.legExtension01,
      1.0,
      dt / crabLegExtensionDuration,
    );

    // Ordering keeps the original mapping: left = +1, right = -1.
    final horizontal = input.axis(GameAction.right, GameAction.left);
    final movement01 = horizontal.abs().clamp(0.0, 1.0).toDouble();
    v.gaitPhase = advanceCrabGaitPhase(v.gaitPhase, movement01, dt);
    final direction = horizontal == 0 ? 1.0 : horizontal.sign.toDouble();

    for (final leg in v.allLegs) {
      final sample = sampleCrabLegGait(
        globalExtension: v.legExtension01,
        extensionDelay: leg.extensionDelay,
        movement01: movement01,
        direction: direction,
        gaitPhase: v.gaitPhase,
        phaseOffset: leg.phaseOffset,
      );
      final basePose = mixCrabLegPose(
        leg.collapsedPose,
        leg.extendedPose,
        sample.extension,
      );
      _applyLegPose(leg, basePose, sample.lift, sample.stride, sample.bend);
    }
  });
}

/// Restores the player's body and pose for a fresh run (the knockback is
/// replaced wholesale by [attachPlayerKnockback]). Each feature resets its
/// own state in `OnEnter(GameStatus.playing)`; the rules feature only
/// resets what it owns (run clock, camera).
void resetPlayerOnRunStart(World world) {
  world.query2<SceneNode, PlayerVisuals>(require: const [Player]).each((
    entity,
    ref,
    visuals,
  ) {
    final body = ref.component<RapierRigidBody>();
    if (body != null) {
      body
        ..type = BodyType.kinematic
        ..linearVelocity = Vector3.zero()
        ..angularVelocity = Vector3.zero();
    }
    ref.node.localTransform = Matrix4.translation(
      Vector3(0, playerStartY, playerStartZ),
    );
    visuals.resetLegs();
  });
}
