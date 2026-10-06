part of '../towers.dart';

void placeTowers(World world) {
  final kind = world.resource<BuildChoice>().kind;
  for (final request in world.events<PlaceTowerRequested>()) {
    final ground = groundAt(world, request.position, request.viewSize);
    if (ground == null) {
      world.resource<BuildChoice>().refusal = Refusal.edge;
    } else {
      placeTowerAt(world, kind, ground);
    }
  }
}

Vector3? groundAt(World world, Offset point, Size viewSize) {
  final scene = world.resource<Scene>();
  final camera = scene.camera;
  if (camera == null) return null;
  final ray = camera.screenPointToRay(point, viewSize);
  return scene
      .raycast(ray, where: (node) => node.name == groundNodeName)
      ?.worldPoint;
}

Refusal? whyNotPlace(World world, TowerKind kind, Vector3 ground) {
  if (world.resource<Gold>().value < kind.cost) return Refusal.gold;
  if (ground.x.abs() > boardEdge || ground.z.abs() > boardEdge) {
    return Refusal.edge;
  }
  if (onTowerPath(ground.x, ground.z)) return Refusal.road;
  if (onDecor(ground.x, ground.z, towerRadius)) return Refusal.decor;
  if (_occupied(world, ground)) return Refusal.occupied;
  return null;
}

bool canPlaceTowerAt(World world, TowerKind kind, Vector3 ground) =>
    whyNotPlace(world, kind, ground) == null;

bool placeTowerAt(World world, TowerKind kind, Vector3 ground) {
  final refusal = whyNotPlace(world, kind, ground);
  world.resource<BuildChoice>().refusal = refusal;
  if (refusal != null) return false;
  world.resource<Gold>().value -= kind.cost;
  final at = Vector3(ground.x, towerRadius, ground.z);
  world.spawn(towerBundle(world, kind, at));
  return true;
}

bool _occupied(World world, Vector3 ground) => world
    .query<SceneTransform>(require: const [Tower])
    .any(
      (_, at) =>
          Vector2(
            at.translation.x - ground.x,
            at.translation.z - ground.z,
          ).length <
          towerFootprint,
    );

void fireGuns(World world) {
  final creeps = _creeps(world);
  world.query2<Gun, SceneTransform>().each((tower, gun, at) {
    gun.cooldown.tick(world.dt);
    if (!gun.cooldown.finished) return;
    final target = _nearest(creeps, at.translation, boltRange);
    if (target == null) return;
    final (victim, victimAt) = target;
    world.emit(DamageDealt(victim, boltDamage));
    gun.cooldown.reset();
    _aimBeam(world.tryGet<TowerBeam>(tower), at.translation, victimAt);
  });
}

void firePulses(World world) {
  final creeps = _creeps(world);
  world.query2<Pulser, SceneTransform>().each((tower, pulser, at) {
    pulser.cooldown.tick(world.dt);
    if (!pulser.cooldown.finished) return;
    final inRange = [
      for (final (creep, creepAt) in creeps)
        if (creepAt.distanceTo(at.translation) < pulseRange) creep,
    ];
    if (inRange.isEmpty) return;
    for (final creep in inRange) {
      world.emit(DamageDealt(creep, pulseDamage));
    }
    pulser.cooldown.reset();
    world.tryGet<PulseRing>(tower)?.fade.reset();
  });
}

void projectShields(World world) {
  final emitters = [
    for (final (_, at)
        in world.query<SceneTransform>(require: const [ShieldEmitter]).records)
      at.translation,
  ];
  world.query<SceneTransform>(require: const [Tower]).each((tower, at) {
    final covered = emitters.any(
      (emitter) => emitter.distanceTo(at.translation) < shieldRange,
    );
    final shielded = world.has<Shield>(tower);
    if (covered && !shielded) world.add(tower, Shield(shieldStrength));
    if (!covered && shielded) world.remove<Shield>(tower);
  });
}

void animateBeams(World world) {
  world.query<TowerBeam>().each((_, beam) {
    beam.fade.tick(world.dt);
    beam.node.visible = !beam.fade.finished;
    beam.material.baseColorFactor.a = beam.fade.value;
  });
}

void animateRings(World world) {
  world.query<PulseRing>().each((_, ring) {
    ring.fade.tick(world.dt);
    ring.node.visible = !ring.fade.finished;
    ring.material.baseColorFactor.a = ring.fade.value;
    final radius = pulseRange * (1 - ring.fade.value).clamp(0.1, 1.0);
    ring.node.localTransform = Matrix4.translationValues(
      0,
      0.1 - towerRadius,
      0,
    )..scaleByDouble(radius, 1, radius, 1);
  });
}

void spawnGhost(World world) => world.spawn(ghostBundle());

void previewPlacement(World world) {
  final pointer = world.resource<BoardPointer>();
  final kind = world.resource<BuildChoice>().kind;
  final position = pointer.position;
  final playing = world.state<GameStatus>() == GameStatus.playing;
  final ground = position == null || !playing
      ? null
      : groundAt(world, position, pointer.viewSize);
  final refusal = ground == null ? null : whyNotPlace(world, kind, ground);
  if (position != null) world.resource<BuildChoice>().refusal = refusal;
  world.query2<SceneTransform, TowerGhost>().each((_, at, ghost) {
    ghost.node.visible = ground != null;
    if (ground == null) return;
    at.translation.setValues(ground.x, towerRadius, ground.z);
    ghost.material.baseColorFactor = refusal == null
        ? ghostOkColor
        : ghostBlockedColor;
  });
}

List<(Entity, Vector3)> _creeps(World world) => [
  for (final (creep, at)
      in world.query<SceneTransform>(require: const [Creep]).records)
    (creep, at.translation),
];

(Entity, Vector3)? _nearest(
  List<(Entity, Vector3)> candidates,
  Vector3 from,
  double within,
) {
  (Entity, Vector3)? best;
  var bestDistance = within;
  for (final candidate in candidates) {
    final distance = candidate.$2.distanceTo(from);
    if (distance >= bestDistance) continue;
    bestDistance = distance;
    best = candidate;
  }
  return best;
}

void _aimBeam(TowerBeam? beam, Vector3 from, Vector3 to) {
  if (beam == null) return;
  final along = to - from;
  final length = along.length;
  if (length == 0) return;
  beam.node.localTransform = Node.lookAtTransform(along.scaled(0.5), along)
    ..scaleByDouble(1, 1, length, 1);
  beam.fade.reset();
}
