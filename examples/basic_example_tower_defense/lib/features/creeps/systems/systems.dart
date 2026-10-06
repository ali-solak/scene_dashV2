part of '../creeps.dart';

void steerCreeps(World world) {
  final creeps = world
      .query3<SceneTransform, Velocity, PathProgress>(require: const [Creep])
      .records
      .toList(growable: false);
  final crowd = [for (final (_, at, _, _) in creeps) at.translation];
  final towers = _towerPositions(world);
  final dt = world.dt;
  for (final (entity, at, velocity, progress) in creeps) {
    final position = at.translation;
    final prey = world.has<Raider>(entity)
        ? _nearest(towers, position, raiderAggro)
        : null;
    final target = prey == null
        ? route[progress.next]
        : _standOff(prey, position);
    final pull = prey == null
        ? Steering.seek(
            position,
            velocity.value,
            target,
            maxSpeed: velocity.maxSpeed,
            maxForce: creepSteering,
          )
        : Steering.arrive(
            position,
            velocity.value,
            target,
            slowingRadius: raiderReach * 2,
            maxSpeed: velocity.maxSpeed,
            maxForce: creepSteering,
          );
    final push = Steering.separation(
      position,
      velocity.value,
      crowd,
      desiredDistance: creepSpacing,
      maxSpeed: velocity.maxSpeed,
      maxForce: creepSteering,
    );
    final force = (pull + push * creepSeparationWeight)..y = 0;
    velocity.value.setFrom(
      Steering.truncate(velocity.value + force * dt, velocity.maxSpeed),
    );
    position.addScaled(velocity.value, dt);
    if (prey != null) continue;
    if (position.distanceTo(target) > waypointReach) continue;
    if (++progress.next < route.length) continue;
    world.emit(const CreepReachedEnd());
    world.despawn(entity);
  }
}

void biteTowers(World world) {
  final towers = world
      .query<SceneTransform>(require: const [Tower])
      .records
      .toList(growable: false);
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
  world.query2<Health, SceneTransform>(require: const [Creep]).each((
    _,
    health,
    at,
  ) {
    final left = (health.current / health.max).clamp(0.0, 1.0);
    at.scale.setValues(1, 1, 1);
    at.scale.scale(creepMinScale + (1 - creepMinScale) * left);
  });
}

List<Vector3> _towerPositions(World world) => [
  for (final (_, at)
      in world.query<SceneTransform>(require: const [Tower]).records)
    at.translation,
];

Vector3? _nearest(List<Vector3> points, Vector3 from, double within) {
  Vector3? best;
  var bestDistance = within;
  for (final point in points) {
    final distance = point.distanceTo(from);
    if (distance >= bestDistance) continue;
    bestDistance = distance;
    best = point;
  }
  return best;
}

Vector3 _standOff(Vector3 prey, Vector3 from) {
  final away = (from - prey)..y = 0;
  if (away.length2 == 0) return prey;
  return prey + away.normalized() * raiderStandOff;
}
