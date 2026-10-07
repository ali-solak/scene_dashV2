part of '../creeps.dart';

void moveCreeps(World world) {
  final towers = world.query<SceneTransform>().having<Tower>().snapshot();
  final dt = world.dt;
  world.query3<SceneTransform, Speed, PathProgress>().having<Creep>().each((
    creep,
    at,
    speed,
    progress,
  ) {
    final step = speed.value * dt;
    final tower = world.has<Raider>(creep)
        ? _nearestTower(towers, at.translation)
        : null;
    if (tower != null) {
      _walk(at.translation, tower, step, stopShort: raiderReach * 0.8);
      return;
    }
    if (!_walk(at.translation, route[progress.next], step)) return;
    if (++progress.next < route.length) return;
    world.emit(const CreepReachedEnd());
    world.despawn(creep);
  });
}

void biteTowers(World world) {
  final towers = world.query<SceneTransform>().having<Tower>().snapshot();
  world.query2<Raider, SceneTransform>().each((_, raider, at) {
    raider.bite.tick(world.dt);
    if (!raider.bite.finished) return;
    for (final (tower, towerAt) in towers) {
      final distance = towerAt.translation.distanceTo(at.translation);
      if (distance > raiderReach) continue;
      world.emit(DamageDealt(tower, raiderBite));
      raider.bite.reset();
      return;
    }
  });
}

void shrinkWithHealth(World world) {
  world.query2<Health, SceneTransform>().having<Creep>().each((_, health, at) {
    final left = (health.current / health.max).clamp(0.0, 1.0);
    at.scale.setValues(1, 1, 1);
    at.scale.scale(creepMinScale + (1 - creepMinScale) * left);
  });
}

Vector3? _nearestTower(List<(Entity, SceneTransform)> towers, Vector3 from) {
  Vector3? nearest;
  var nearestDistance = raiderAggro;
  for (final (_, at) in towers) {
    final distance = at.translation.distanceTo(from);
    if (distance >= nearestDistance) continue;
    nearestDistance = distance;
    nearest = at.translation;
  }
  return nearest;
}

bool _walk(
  Vector3 position,
  Vector3 target,
  double step, {
  double stopShort = 0,
}) {
  final offset = (target - position)..y = 0;
  final remaining = offset.length - stopShort;
  if (remaining <= 0) return true;
  position.addScaled(offset.normalized(), remaining < step ? remaining : step);
  return remaining <= step;
}
