part of '../towers.dart';

void placeTowers(World world) {
  final gold = world.resource<Gold>();
  for (final request in world.events<PlaceTowerRequested>()) {
    final spot = Vector3(request.x, towerRadius, request.z);
    if (gold.value < towerCost) continue;
    if (onTowerPath(request.x, request.z)) continue;
    if (_occupied(world, spot)) continue;
    gold.value -= towerCost;
    world.spawn(towerBundle(spot));
  }
}

bool _occupied(World world, Vector3 spot) => world
    .query<SceneTransform>(require: const [Tower])
    .any((_, at) => at.translation.distanceTo(spot) < towerFootprint);

void giveTowersBodies(World world) => world
    .entitiesWith(require: const [Tower], exclude: const [NodeRef])
    .each((entity) {
      final (ref, beam) = towerVisuals();
      world
        ..add(entity, ref)
        ..add(entity, beam);
    });

void fireTowers(World world) {
  final creeps = world
      .query2<Health, SceneTransform>(require: const [Creep])
      .records
      .toList(growable: false);
  for (final (entity, tower, at)
      in world.query2<Tower, SceneTransform>().records) {
    tower.cooldown.tick(world.dt);
    if (!tower.cooldown.finished) continue;

    final target = _nearestCreep(creeps, at.translation);
    if (target == null) continue;
    final (victim, victimAt) = target;

    victim.current -= towerDamage;
    tower.cooldown.reset();
    _aimBeam(world.tryGet<TowerBeam>(entity), at.translation, victimAt);
  }
}

(Health, Vector3)? _nearestCreep(
  List<(Entity, Health, SceneTransform)> creeps,
  Vector3 from,
) {
  (Health, Vector3)? best;
  var nearest = towerRange;
  for (final (_, health, at) in creeps) {
    final distance = at.translation.distanceTo(from);
    if (distance >= nearest) continue;
    nearest = distance;
    best = (health, at.translation);
  }
  return best;
}

void _aimBeam(TowerBeam? beam, Vector3 from, Vector3 to) {
  if (beam == null) return;
  final along = to - from;
  if (along.length < 1e-4) return;

  beam.node.localTransform = Node.lookAtTransform(along.scaled(0.5), along)
    ..scaleByDouble(1, 1, along.length, 1);
  beam.fade.reset();
}

void animateBeams(World world) {
  world.query<TowerBeam>().each((_, beam) {
    beam.fade.tick(world.dt);
    beam.node.visible = !beam.fade.finished;
    beam.material.baseColorFactor.a = beam.fade.value;
  });
}
