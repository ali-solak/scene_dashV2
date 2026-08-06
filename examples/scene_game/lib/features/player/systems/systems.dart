part of '../player.dart';

void spawnPlayer(World world) {
  world.spawn(playerBundle());
}

void attachPlayerKnockback(World world) {
  final player = world.entitiesWith(require: const [Player]).firstOrNull;
  if (player == null) return;
  world.add(player, PlayerKnockback());
}

void movePlayer(World world) {
  final input = world.buttons<GameAction>();
  final dt = world.dt;
  world.query2<PlayerKnockback, NodeRef>(require: const [Player]).each((
    entity,
    knockback,
    ref,
  ) {
    final controller = ref.component<KinematicCharacterController>();
    if (controller == null) return;

    final node = ref.node;
    _snapToRamp(node, knockback);

    final m = node.localTransform.storage;
    final positionY = m[13];
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
  // Reassignment marks the transform dirty.
  node.localTransform = transform;
  knockback.ground();
}

void animateCrabLegs(World world) {
  final input = world.buttons<GameAction>();
  final dt = world.dt;
  world.query<PlayerVisuals>(require: const [Player]).each((entity, v) {
    v.legExtension01 = approach(
      v.legExtension01,
      1.0,
      dt / crabLegExtensionDuration,
    );

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

void resetPlayerOnRunStart(World world) {
  world.query2<NodeRef, PlayerVisuals>(require: const [Player]).each((
    entity,
    ref,
    visuals,
  ) {
    final body = ref.component<RigidBody>();
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
