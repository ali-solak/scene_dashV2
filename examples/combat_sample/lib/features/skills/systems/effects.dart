part of '../skills.dart';

void installSkillEffects(GameBuilder game) {
  game
    ..observe<Burning>(
      onAdd: (world, entity, _) => world.tryGet<Brawler>(entity)?.sinceHurt = 0,
    )
    ..group(
      inSet: GameSets.actions,
      runIf: inState(GameStatus.fighting),
      (game) => game
        ..addSystem(
          Schedules.fixedUpdate,
          tickBurning,
          reads: const {Health},
          writes: const {Burning},
        )
        ..addSystem(
          Schedules.fixedUpdate,
          tickLavaPits,
          reads: const {Enemy, Health, SceneTransform, Burning},
          writes: const {LavaPit},
          after: const [tickBurning],
        )
        ..addSystem(
          Schedules.fixedUpdate,
          tickBarriers,
          writes: const {Barrier},
        ),
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
    world.query2<Health, SceneTransform>().having<Enemy>().each((
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
