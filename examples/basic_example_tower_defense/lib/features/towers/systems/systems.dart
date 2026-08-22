part of '../towers.dart';

void placeTowers(World world) {
  final scene = world.resource<Scene>();
  final camera = scene.camera;
  if (camera == null) return;
  for (final request in world.events<PlaceTowerRequested>()) {
    final ray = camera.screenPointToRay(request.position, request.viewSize);
    final ground = scene
        .raycast(ray, where: (node) => node.name == groundNodeName)
        ?.worldPoint;
    if (ground != null) placeTowerAt(world, ground.x, ground.z);
  }
}

bool placeTowerAt(World world, double x, double z) {
  final gold = world.resource<Gold>();
  final spot = Vector3(x, towerRadius, z);
  if (gold.value < towerCost) return false;
  if (onTowerPath(x, z)) return false;
  if (_occupied(world, spot)) return false;
  gold.value -= towerCost;
  world.spawn(towerBundle(spot));
  return true;
}

bool _occupied(World world, Vector3 spot) => world
    .query<SceneTransform>(require: const [Tower])
    .any((_, at) => at.translation.distanceTo(spot) < towerFootprint);

void fireTowers(World world) {
  final creeps = world
      .query2<Health, SceneTransform>(require: const [Creep])
      .records
      .toList(growable: false);

  final dt = world.dt;
  world.query2<Tower, SceneTransform>().each((entity, tower, towerTransform) {
    tower.cooldown.tick(dt);
    if (!tower.cooldown.finished) return;

    final target = _nearestCreep(creeps, towerTransform.translation);
    if (target == null) return;
    final (victim, victimAt) = target;

    victim.current -= towerDamage;
    tower.cooldown.reset();
    _aimBeam(
      world.tryGet<TowerBeam>(entity),
      towerTransform.translation,
      victimAt,
    );
  });
}

(Health, Vector3)? _nearestCreep(
  List<(Entity, Health, SceneTransform)> creeps,
  Vector3 from,
) {
  (Health, Vector3)? best;
  var nearestSquared = towerRange * towerRange;
  for (final (_, health, at) in creeps) {
    if (health.current <= 0) continue;
    final distanceSquared = at.translation.distanceToSquared(from);
    if (distanceSquared >= nearestSquared) continue;
    nearestSquared = distanceSquared;
    best = (health, at.translation);
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

void animateBeams(World world) {
  world.query<TowerBeam>().each((_, beam) {
    beam.fade.tick(world.dt);
    beam.node.visible = !beam.fade.finished;
    beam.material.baseColorFactor.a = beam.fade.value;
  });
}
