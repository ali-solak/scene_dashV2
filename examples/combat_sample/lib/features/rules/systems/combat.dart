part of '../rules.dart';

/// Hit resolution: both fighters' strike windows emit [HitLanded], and
/// one system serves every hit, so damage, poise, and death have exactly
/// one path.
void installHitResolution(GameBuilder game) {
  game
    ..addSystem(
      Schedules.fixedUpdate,
      resolveStrikes,
      inSet: GameSets.resolution,
      reads: const {
        Player,
        Enemy,
        Fighter,
        Brawler,
        Health,
        PlayerMotion,
        SceneTransform,
      },
      runIf: inState(GameStatus.fighting),
    )
    ..addSystem(
      Schedules.fixedUpdate,
      applyDamage,
      inSet: GameSets.resolution,
      reads: const {Enemy, SceneNode},
      writes: const {
        Fighter,
        Brawler,
        Health,
        Knockback,
        Barrier,
        PendingCorpse,
      },
      after: const [resolveStrikes],
      runIf: inState(GameStatus.fighting),
    )
    ..addSystem(
      Schedules.fixedUpdate,
      clearBufferOnStagger,
      inSet: GameSets.resolution,
      reads: const {Fighter},
      after: const [applyDamage],
    );
}

/// The strike windows are the machines' edges: the player's
/// `justEntered(active)` and a barbarian's `justEntered(swing)` each check
/// reach + frontal arc once, both directions, and emit [HitLanded] for
/// every connect. One swing can never land twice; the edge is one tick
/// wide.
void resolveStrikes(World world) {
  final playerRow = world
      .query3<Fighter, PlayerMotion, SceneTransform>(require: const [Player])
      .firstOrNull;
  if (playerRow == null) return;
  final (player, fighter, motion, playerTransform) = playerRow;

  // A swing lands one connect; a spin lands one every `heavyHitInterval`
  // as the axe comes around. `strikeHits` counts taps already fired this
  // active phase, so each is emitted exactly once across the fixed steps.
  final phase = fighter.phase;
  if (phase.justEntered(CombatPhase.active)) fighter.strikeHits = 0;
  if (phase.state == CombatPhase.active) {
    final due = fighter.heavy
        ? (phase.elapsed / heavyHitInterval).floor() + 1
        : 1;
    while (fighter.strikeHits < due) {
      fighter.strikeHits++;
      _strikeEnemies(world, fighter, motion, playerTransform);
    }
  }

  world.query2<Brawler, SceneTransform>(require: const [Enemy]).each((
    enemy,
    brawler,
    enemyTransform,
  ) {
    if (brawler.phase.justEntered(BrawlPhase.swing) &&
        withinArc(
          from: enemyTransform,
          facing: brawler.facing,
          to: playerTransform,
          reach: brawlerReach,
          halfArc: brawlerStrikeHalfArc,
        )) {
      final damage = brawlerDamage * brawler.power;
      final shove = awayFrom(
        enemyTransform,
        playerTransform,
        brawlerKnockback * brawler.power,
      );
      // A giant doesn't shove you, it sends you flying.
      if (brawler.giant) shove.y = giantLaunchSpeed;
      world.emit(
        HitLanded(
          player,
          damage,
          knockback: shove,
          // Poise: an ordinary swing hurts and shoves but does not cancel
          // what you were doing; a giant's blow does.
          stagger: damage >= playerPoiseThreshold,
        ),
      );
    }
  });
}

/// One tap of the player's swing: a connect to every living enemy inside
/// the strike arc. Called once for a chop, once per sweep tick for the
/// spin; every connect staggers, so a body in the spin reacts each time
/// the axe comes around.
void _strikeEnemies(
  World world,
  Fighter fighter,
  PlayerMotion motion,
  SceneTransform playerTransform,
) {
  final damage = fighter.heavy ? heavyDamage : lightDamage;
  final push = fighter.heavy ? heavyKnockback : lightKnockback;
  world.query2<Health, SceneTransform>(require: const [Enemy]).each((
    enemy,
    health,
    enemyTransform,
  ) {
    if (!health.alive) return;
    if (withinArc(
      from: playerTransform,
      facing: motion.facing,
      to: enemyTransform,
      reach: playerReach,
      halfArc: playerStrikeHalfArc,
    )) {
      world.emit(
        HitLanded(
          enemy,
          damage,
          heavy: fighter.heavy,
          knockback: awayFrom(playerTransform, enemyTransform, push),
        ),
      );
    }
  });
}

/// Serves every [HitLanded]: an i-framed roll passes through cleanly;
/// otherwise health drops, the victim staggers, and a barbarian at zero
/// enters `dying` (falling, then dissolving, then despawning so the waves
/// feature can recycle its pooled model).
void applyDamage(World world) {
  for (final hit in world.events<HitLanded>()) {
    final fighter = world.tryGet<Fighter>(hit.target);
    if (fighter != null) {
      if (fighter.iFramed) continue; // rolled through it
      // Launched by a giant: untouchable through the arc (the flight is
      // an escape, never a juggle). Only the player gets this; an
      // airborne barbarian is still hittable.
      if (world.tryGet<Knockback>(hit.target)?.airborne ?? false) continue;
    }

    // The barrier eats the blow whole (no health, no shove, no stagger)
    // and spends one charge, whatever the blow was worth. Blows only:
    // letting DoT ticks spend charges would drain a full barrier in
    // under a second of lava.
    final barrier = hit.impact ? world.tryGet<Barrier>(hit.target) : null;
    if (barrier != null && !barrier.spent) {
      final broke = barrier.absorb(push: hit.knockback);
      // A block sparks so it reads as the barrier taking the hit, not the
      // hit quietly not happening (no hitstop; the freeze read as lag).
      final at = world.tryGet<SceneTransform>(hit.target);
      if (at != null) {
        spawnImpactBurst(
          world,
          Vector3(
            at.translation.x,
            at.translation.y + impactBurstHeight,
            at.translation.z,
          ),
          heavy: hit.heavy,
        );
      }
      if (broke) world.remove<Barrier>(hit.target);
      continue;
    }

    final health = world.tryGet<Health>(hit.target);
    final wasAlive = health?.alive ?? true;
    if (health != null) {
      health.current = math.max(0, health.current - hit.damage);
    }

    // The shove: the physical half of the feedback.
    final push = hit.knockback;
    if (push != null) {
      final knockback = world.tryGet<Knockback>(hit.target);
      knockback?.shove(push);
    }

    // The sparks: the visual half (a no-op headless).
    final at = hit.impact ? world.tryGet<SceneTransform>(hit.target) : null;
    if (at != null) {
      spawnImpactBurst(
        world,
        Vector3(
          at.translation.x,
          at.translation.y + impactBurstHeight,
          at.translation.z,
        ),
        heavy: hit.heavy,
      );
    }

    // Poise: only a blow heavy enough breaks the player's action.
    if (hit.stagger) fighter?.phase.go(CombatPhase.staggered);

    // The flinch: poise lets an ordinary swing through, but the fighter
    // still has to look hit. Visual only; nothing here touches the
    // machine.
    if (fighter != null && hit.damage > 0) {
      fighter.sinceHurt = 0;
    }

    final brawler = world.tryGet<Brawler>(hit.target);
    if (brawler != null && wasAlive) {
      if (health != null && !health.alive) {
        brawler.phase.go(BrawlPhase.dying);
        world.add(
          hit.target,
          const PendingCorpse(),
          removeAfter: corpseHitSeconds,
        );
        // The kill pays out; the wave watches the living count.
        world.resource<Score>().award(
          brawler.giant ? giantPoints : enemyPoints,
        );
        // Ragdoll, then dissolve, then despawn; waves recycle the slot
        // (and the pooled model, via the ModelSlot observer).
        const deathSeconds = dissolveDelaySeconds + dissolveSeconds;
        world.add(hit.target, const Dissolving(), removeAfter: deathSeconds);
        world.add(hit.target, DespawnAfter(deathSeconds));
      } else if (hit.stagger) {
        // DoT ticks arrive faster than the stagger window, so an ungated
        // stagger here stunlocked anything standing in fire. Those ticks
        // flinch once on the catch instead (a `Burning` onAdd sets
        // `Brawler.sinceHurt`; see `installSkills`).
        brawler.phase.go(BrawlPhase.staggered);
      }
    }
  }
}
