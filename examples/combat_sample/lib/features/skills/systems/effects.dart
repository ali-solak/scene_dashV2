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
    // No knockback and no stagger: a burn should never yank a barbarian
    // out of the fight you are having with it.
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

/// Ages every barrier's block flare. The clock is GAMEPLAY's (L2/L3): the
/// sphere reads it and never writes it, so the effect cannot drift from
/// the state it is supposed to be showing.
void tickBarriers(World world) {
  final dt = world.dt;
  world.query<Barrier>().each((entity, barrier) {
    barrier.sinceBlock += dt;
  });
}

/// Cooks whatever is standing in a pit. Damage is metered per pit, not
/// per victim, so walking through one costs the same wherever you enter.
///
/// Deliberately O(pits × enemies), and fine at this game's scale BY
/// INVARIANT: the skill's cooldown outlasts the pit's lifetime, so the
/// player holds at most one live pit (plus a beat of overlap). If a
/// future design allows concurrent zones, reach for a spatial grid or an
/// enemy→zone ownership pass instead of widening this loop.
void tickLavaPits(World world) {
  final dt = world.dt;
  world.query2<LavaPit, SceneTransform>().each((entity, pit, at) {
    pit.elapsed += dt;
    pit.sinceTick += dt;
    // The BOG runs every step (so it can't be walked through); the COOK is
    // metered on the pit's own tick.
    final cook = pit.sinceTick >= lavaTickSeconds;
    if (cook) pit.sinceTick -= lavaTickSeconds;
    world.query2<Health, SceneTransform>(require: const [Enemy]).each((
      enemy,
      health,
      standing,
    ) {
      if (!health.alive) return;
      if (planarDistance(at, standing) > lavaPitRadius) return;
      // Bogged down while standing in it, refreshed every step so it wears
      // off just after they wade out ([lavaMireLinger]).
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
      // Alight: the flame visual is driven off [Burning], so without this
      // the lava cooked people without ever lighting them. Never weaker
      // than a burn already carried, so a pit cannot downgrade a gush's
      // fire.
      final carried = world.tryGet<Burning>(enemy)?.damage ?? 0;
      world.add(
        enemy,
        Burning(math.max(carried, lavaBurnTickDamage)),
        removeAfter: lavaBurnSeconds,
      );
    });
  });
}
