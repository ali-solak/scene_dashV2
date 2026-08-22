part of '../creeps.dart';

void spawnCreep(World world) => world.spawn(creepBundle());

void walkPath(World world) {
  final creeps = world.query2<SceneTransform, PathProgress>(
    require: const [Creep],
  );
  creeps.each((entity, at, progress) {
    final target = towerPath[progress.next];
    final step = creepSpeed * world.dt;
    at.x = moveToward(at.x, target.x, step);
    at.z = moveToward(at.z, target.z, step);
    if (at.x != target.x || at.z != target.z) return;
    if (++progress.next < towerPath.length) return;
    world.emit(const CreepReachedEnd());
    world.despawn(entity);
  });
}

void reapCreeps(World world) {
  world.query<Health>(require: const [Creep]).each((entity, health) {
    if (health.current > 0) return;
    world.emit(const CreepKilled(creepBounty));
    world.despawn(entity);
  });
}
