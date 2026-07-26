part of '../skills.dart';

/// The lasting effects each cast leaves behind: burn damage over time,
/// the barrier's charges, and the lava pits' mire.
void installSkillEffects(GameBuilder game) {
  game
    ..registerComponent<Burning>()
    ..registerComponent<LavaPit>()
    ..registerComponent<Barrier>()
    // Fire causes one flinch when first applied.
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

/// The burn's damage-over-time. The component's own `removeAfter:` clock
/// ends it; this only has to meter the ticks.
void tickBurning(World world) {
  final dt = world.dt;
  world.query2<Burning, Health>().each((entity, burning, health) {
    if (!health.alive) return;
    burning.sinceTick += dt;
    if (burning.sinceTick < burnTickSeconds) return;
    burning.sinceTick -= burnTickSeconds;
    // Burn damage has no impact reaction.
    world.emit(
      HitLanded(
        entity,
        burning.damage,
        stagger: false,
        impact: false, // a burn tick, not a blow
      ),
    );
  });
}

/// Advances barrier hit effects.
void tickBarriers(World world) {
  final dt = world.dt;
  world.query<Barrier>().each((entity, barrier) {
    barrier.sinceBlock += dt;
  });
}

/// Applies damage from active lava pits.
void tickLavaPits(World world) {
  final dt = world.dt;
  world.query2<LavaPit, SceneTransform>().each((entity, pit, at) {
    pit.elapsed += dt;
    pit.sinceTick += dt;
    // Apply mire continuously and damage on ticks.
    final cook = pit.sinceTick >= lavaTickSeconds;
    if (cook) pit.sinceTick -= lavaTickSeconds;
    world.query2<Health, SceneTransform>(require: const [Enemy]).each((
      enemy,
      health,
      standing,
    ) {
      if (!health.alive) return;
      if (planarDistance(at, standing) > lavaPitRadius) return;
      // Refresh mire while inside.
      world.add(enemy, const Mired(), removeAfter: lavaMireLinger);
      if (!cook) return;
      world.emit(
        HitLanded(
          enemy,
          pit.damage,
          stagger: false,
          impact: false, // standing in lava is not a hit to freeze on
        ),
      );
      // Apply the strongest active burn.
      final carried = world.tryGet<Burning>(enemy)?.damage ?? 0;
      world.add(
        enemy,
        Burning(math.max(carried, lavaBurnTickDamage)),
        removeAfter: lavaBurnSeconds,
      );
    });
  });
}
