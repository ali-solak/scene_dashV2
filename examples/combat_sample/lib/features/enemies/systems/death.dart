part of '../enemies.dart';

void installEnemyDeath(GameBuilder game) {
  game
    ..registerComponent<PendingCorpse>()
    ..registerComponent<PhysicsCorpse>()
    ..registerComponent<Dissolving>()
    ..observe<PendingCorpse>(onRemove: launchPhysicsCorpse)
    ..addSystem(
      Schedules.update,
      dustCorpseLandings,
      inSet: GameSets.logic,
      reads: const {Enemy},
      writes: const {PhysicsCorpse},
      runIf: hasResource<Scene>(),
    );
}

void launchPhysicsCorpse(World world, Entity entity, PendingCorpse pending) {
  final row = world.tryGet3<Brawler, NodeRef, Knockback>(entity);
  if (row == null || world.has<PhysicsDriven>(entity)) return;
  final (brawler, ref, knockback) = row;
  final seed = brawler.wobbleSeed + brawler.wobble;
  final (velocity, spin) = _corpseMotion(
    knockback.velocity,
    brawler.facing,
    seed,
  );

  final halfExtents = corpseHalfExtents.clone();
  if (brawler.giant) halfExtents.scale(giantScale);
  final body = RigidBody(
    type: BodyType.dynamic_,
    linearVelocity: velocity,
    angularVelocity: spin,
    linearDamping: corpseLinearDamping,
    angularDamping: corpseAngularDamping,
    ccdEnabled: true,
  );
  final collider = Collider(
    shape: BoxShape(halfExtents: halfExtents),
    material: corpseMaterial,
    collisionLayer: PhysicsLayers.fighter,
    collisionMask: PhysicsLayers.ground,
    localPose: Matrix4.translation(Vector3(0, halfExtents.y, 0)),
  );
  final commands = world.resource<SceneCommands>();

  world.tryGet<EnemyAnimator>(entity)?.freeze();
  world.add(entity, const PhysicsDriven());
  world.add(entity, PhysicsCorpse(body));
  commands
    ..attach(ref.node, body)
    ..attach(ref.node, collider);
  _dropAxe(world, entity, commands, velocity, seed);
}

void _dropAxe(
  World world,
  Entity entity,
  SceneCommands commands,
  Vector3 corpseVelocity,
  double seed,
) {
  final axe = world.tryGet<ModelSlot>(entity)?.axe;
  if (axe == null || axe.parent == null) return;
  // Keep the drawn pose while reparenting.
  axe.localTransform = axe.globalTransform.clone();

  final body = RigidBody(
    type: BodyType.dynamic_,
    linearVelocity: Vector3(
      corpseVelocity.x * axeDropCarry + math.sin(seed * 5.3) * axeDropToss,
      corpseVelocity.y * axeDropCarry + axeDropToss,
      corpseVelocity.z * axeDropCarry + math.cos(seed * 5.3) * axeDropToss,
    ),
    angularVelocity: Vector3(
      math.sin(seed * 3.1),
      math.cos(seed * 7.7),
      math.sin(seed * 11.3),
    )..scale(axeDropSpin),
    linearDamping: corpseLinearDamping,
    angularDamping: corpseAngularDamping,
    ccdEnabled: true,
  );
  final collider = Collider(
    shape: BoxShape(halfExtents: axeHalfExtents),
    material: corpseMaterial,
    collisionLayer: PhysicsLayers.fighter,
    collisionMask: PhysicsLayers.ground,
  );
  commands
    ..remove(axe)
    ..add(axe)
    ..attach(axe, body)
    ..attach(axe, collider);
}

void dustCorpseLandings(World world) {
  world.query<PhysicsCorpse>(require: const [Enemy]).each((entity, corpse) {
    if (corpse.bursts >= corpseDustMaxBursts) return;
    final body = corpse.body;
    if (body.handle == null) return;
    final velocity = body.linearVelocity;
    final landed =
        corpse.fallSpeed < -corpseDustMinFallSpeed && velocity.y > -0.5;
    corpse.fallSpeed = velocity.y;
    if (!landed) return;
    corpse.bursts++;
    final heading = Vector3(velocity.x, 0, velocity.z);
    if (heading.length2 < 1e-4) heading.setValues(0, 0, 1);
    final at = body.node.globalTransform.getTranslation()..y = 0;
    spawnDashDust(world, at, heading);
  });
}

(Vector3, Vector3) _corpseMotion(Vector3 incoming, double facing, double seed) {
  final velocity = Vector3(0, math.max(incoming.y, corpseHopVelocity), 0);
  final spin = Vector3(math.cos(facing), 0, -math.sin(facing))
    ..scale(corpseTumbleMin);
  final horizontal = Vector3(incoming.x, 0, incoming.z);
  if (horizontal.length2 > 1e-6) {
    horizontal.normalize();
    velocity
      ..x = horizontal.x * corpseLaunchSpeed
      ..z = horizontal.z * corpseLaunchSpeed;
    spin
      ..setValues(horizontal.z, 0, -horizontal.x)
      ..scale(
        math.max(corpseTumbleMin, corpseLaunchSpeed * corpseTumbleFactor),
      );
  }
  spin.y = math.sin(seed * 12.9898) * 0.5 * corpseYawSpin;
  return (velocity, spin);
}
