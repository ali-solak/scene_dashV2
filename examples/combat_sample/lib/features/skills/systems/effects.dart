part of '../skills.dart';

void installSkillEffects(GameBuilder game) {
  game
    ..registerComponent<Burning>()
    ..registerComponent<LavaPit>()
    ..registerComponent<Barrier>()
    ..observe<Burning>(
      onAdd: (world, entity, _) => world.tryGet<Brawler>(entity)?.sinceHurt = 0,
    )
    ..addSystem(
      Schedules.fixedUpdate,
      tickBurning,
      inSet: GameSets.actions,
      reads: const {Health},
      writes: const {Burning},
      runIf: inState(GameStatus.fighting),
    )
    ..addSystem(
      Schedules.fixedUpdate,
      tickLavaPits,
      inSet: GameSets.actions,
      reads: const {Enemy, Health, SceneTransform, Burning},
      writes: const {LavaPit},
      after: const [tickBurning],
      runIf: inState(GameStatus.fighting),
    )
    ..addSystem(
      Schedules.fixedUpdate,
      tickBarriers,
      inSet: GameSets.actions,
      writes: const {Barrier},
      runIf: inState(GameStatus.fighting),
    );
}

void tickBurning(World world) {
  final dt = world.dt;
  world.query2<Burning, Health>().each((entity, burning, health) {
    if (!health.alive) return;
    burning.sinceTick += dt;
    if (burning.sinceTick < burnTickSeconds) return;
    burning.sinceTick -= burnTickSeconds;
    world.emit(
      HitLanded(entity, burning.damage, stagger: false, impact: false),
    );
  });
}

void tickBarriers(World world) {
  final dt = world.dt;
  world.query<Barrier>().each((entity, barrier) {
    barrier.sinceBlock += dt;
  });
}

void tickLavaPits(World world) {
  final dt = world.dt;
  world.query2<LavaPit, SceneTransform>().each((entity, pit, at) {
    pit.elapsed += dt;
    pit.sinceTick += dt;
    final cook = pit.sinceTick >= lavaTickSeconds;
    if (cook) pit.sinceTick -= lavaTickSeconds;
    world.query2<Health, SceneTransform>(require: const [Enemy]).each((
      enemy,
      health,
      standing,
    ) {
      if (!health.alive) return;
      if (planarDistance(at, standing) > lavaPitRadius) return;
      world.add(enemy, const Mired(), removeAfter: lavaMireLinger);
      if (!cook) return;
      world.emit(HitLanded(enemy, pit.damage, stagger: false, impact: false));
      final carried = world.tryGet<Burning>(enemy)?.damage ?? 0;
      world.add(
        enemy,
        Burning(math.max(carried, lavaBurnTickDamage)),
        removeAfter: lavaBurnSeconds,
      );
    });
  });
}
