part of '../rules.dart';

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
      reads: const {Enemy, NodeRef},
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

void resolveStrikes(World world) {
  final row = world
      .query3<Fighter, PlayerMotion, SceneTransform>(require: const [Player])
      .firstOrNull;
  if (row == null) return;
  final (player, fighter, motion, transform) = row;
  _resolvePlayerStrikes(world, fighter, motion, transform);
  _resolveEnemyStrikes(world, player, transform);
}

void _resolvePlayerStrikes(
  World world,
  Fighter fighter,
  PlayerMotion motion,
  SceneTransform transform,
) {
  final phase = fighter.phase;
  if (phase.justEntered(CombatPhase.active)) fighter.strikeHits = 0;
  if (phase.state != CombatPhase.active) return;
  final due = fighter.heavy
      ? (phase.elapsed / heavyHitInterval).floor() + 1
      : 1;
  while (fighter.strikeHits < due) {
    fighter.strikeHits++;
    _strikeEnemies(world, fighter, motion, transform);
  }
}

void _resolveEnemyStrikes(
  World world,
  Entity player,
  SceneTransform playerTransform,
) {
  world.query2<Brawler, SceneTransform>(require: const [Enemy]).each((
    _,
    brawler,
    enemyTransform,
  ) {
    if (!brawler.phase.justEntered(BrawlPhase.swing)) return;
    if (!withinArc(
      from: enemyTransform,
      facing: brawler.facing,
      to: playerTransform,
      reach: brawlerReach,
      halfArc: brawlerStrikeHalfArc,
    )) {
      return;
    }
    final damage = brawlerDamage * brawler.power;
    final shove = awayFrom(
      enemyTransform,
      playerTransform,
      brawlerKnockback * brawler.power,
    );
    if (brawler.giant) shove.y = giantLaunchSpeed;
    world.emit(
      HitLanded(
        player,
        damage,
        knockback: shove,
        stagger: damage >= playerPoiseThreshold,
      ),
    );
  });
}

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

void applyDamage(World world) {
  for (final hit in world.events<HitLanded>()) {
    if (_ignoresHit(world, hit.target)) continue;
    if (_absorbHit(world, hit)) continue;
    _applyHit(world, hit);
  }
}

bool _ignoresHit(World world, Entity target) {
  final fighter = world.tryGet<Fighter>(target);
  return fighter != null &&
      (fighter.iFramed || (world.tryGet<Knockback>(target)?.airborne ?? false));
}

bool _absorbHit(World world, HitLanded hit) {
  final barrier = hit.impact ? world.tryGet<Barrier>(hit.target) : null;
  if (barrier == null || barrier.spent) return false;
  final broke = barrier.absorb(push: hit.knockback);
  _spawnImpact(world, hit);
  if (broke) world.remove<Barrier>(hit.target);
  return true;
}

void _applyHit(World world, HitLanded hit) {
  final health = world.tryGet<Health>(hit.target);
  final wasAlive = health?.alive ?? true;
  if (health != null) {
    health.current = math.max(0, health.current - hit.damage);
  }
  if (hit.knockback case final push?) {
    world.tryGet<Knockback>(hit.target)?.shove(push);
  }
  if (hit.impact) _spawnImpact(world, hit);

  final fighter = world.tryGet<Fighter>(hit.target);
  if (hit.stagger) fighter?.phase.go(CombatPhase.staggered);
  if (fighter != null && hit.damage > 0) fighter.sinceHurt = 0;

  final brawler = world.tryGet<Brawler>(hit.target);
  if (brawler == null || !wasAlive) return;
  if (health != null && !health.alive) {
    _killBrawler(world, hit.target, brawler);
  } else if (hit.stagger) {
    brawler.phase.go(BrawlPhase.staggered);
  }
}

void _spawnImpact(World world, HitLanded hit) {
  final transform = world.tryGet<SceneTransform>(hit.target);
  if (transform == null) return;
  final position = transform.translation.clone()..y += impactBurstHeight;
  spawnImpactBurst(world, position, heavy: hit.heavy);
}

void _killBrawler(World world, Entity entity, Brawler brawler) {
  brawler.phase.go(BrawlPhase.dying);
  world.add(entity, const PendingCorpse(), removeAfter: corpseHitSeconds);
  world.resource<Score>().award(brawler.giant ? giantPoints : enemyPoints);

  const deathSeconds = dissolveDelaySeconds + dissolveSeconds;
  world.add(entity, const Dissolving(), removeAfter: deathSeconds);
  world.add(entity, DespawnAfter(deathSeconds));
}
