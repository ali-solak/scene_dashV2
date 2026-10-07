part of '../feedback.dart';

void installDamageNumbers(GameBuilder game) {
  game
    ..addSystem(
      Schedules.update,
      spawnDamageNumbers,
      inSet: GameSets.logic,
      reads: const {Player, SceneTransform},
      writes: const {DamageNumber},
      runIf: hasResource<Scene>(),
    )
    ..addSystem(
      Schedules.update,
      floatDamageNumbers,
      inSet: GameSets.logic,
      writes: const {DamageNumber},
      after: const [spawnDamageNumbers],
      runIf: hasResource<Scene>(),
    );
}

void spawnDamageNumbers(World world) {
  var spread = 0;
  for (final hit in world.events<DamageDealt>()) {
    final transform = world.tryGet<SceneTransform>(hit.target);
    if (transform == null) continue;
    final side = (spread++ % 3 - 1) * damageNumberSpread;
    final origin = transform.translation.clone()..y += damageNumberHeight;
    final opacity = ValueNotifier<double>(1);
    final node = Node(name: 'damage-number')
      ..frustumCulled = false
      ..addComponent(
        WidgetComponent(
          child: DamageNumberWidget(
            amount: hit.amount,
            weight: hit.weight,
            hurt: world.has<Player>(hit.target),
            ticking: !hit.impact,
            opacity: opacity,
          ),
          size: damageNumberCanvas,
          worldHeight: damageNumberWorldHeight,
          pixelRatio: 1.5,
          input: WidgetInput.manual,
          geometry: widgetQuad(
            size: damageNumberCanvas,
            worldHeight: damageNumberWorldHeight,
          ),
        ),
      );
    world.spawn([
      DamageNumber(
        origin: origin,
        drift: Vector3(-hit.direction.z * side, 0, hit.direction.x * side),
        opacity: opacity,
        node: node,
      ),
      NodeRef(node),
      DespawnAfter(damageNumberSeconds),
    ]);
  }
}

void floatDamageNumbers(World world) {
  final rig = world.resource<CameraRig>();
  world.query<DamageNumber>().each((entity, number) {
    number.age += world.dt;
    final t = (number.age / damageNumberSeconds).clamp(0.0, 1.0);
    final eased = 1 - (1 - t) * (1 - t);
    final position = number.origin + number.drift * eased
      ..y += damageNumberRise * eased;
    final pop = number.age < damageNumberPopSeconds
        ? 1 + damageNumberPop * (1 - number.age / damageNumberPopSeconds)
        : 1.0;
    number.opacity.value = t < 0.6 ? 1 : 1 - (t - 0.6) / 0.4;
    final yaw = math.atan2(
      rig.position.x - position.x,
      rig.position.z - position.z,
    );
    number.node.localTransform = Matrix4.compose(
      position,
      Quaternion.axisAngle(Vector3(0, 1, 0), yaw),
      Vector3.all(pop),
    );
  });
}
