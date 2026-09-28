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
  final interval = fighter.swing.hitInterval;
  final due = interval == null ? 1 : (phase.elapsed / interval).floor() + 1;
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
  final swing = fighter.swing;
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
      halfArc: swing.sweepsAround ? math.pi : playerStrikeHalfArc,
    )) {
      world.emit(
        HitLanded(
          enemy,
          swing.damage,
          weight: fighter.heavy
              ? HitWeight.heavy
              : swing.sweepsAround
              ? HitWeight.finisher
              : HitWeight.light,
          knockback: awayFrom(playerTransform, enemyTransform, swing.knockback),
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

  if (health != null && hit.damage > 0) {
    world.emit(
      DamageDealt(
        hit.target,
        hit.damage,
        weight: hit.weight,
        direction: _planarDirection(hit.knockback),
        impact: hit.impact,
        killed: wasAlive && !health.alive,
      ),
    );
  }

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

Vector3 _planarDirection(Vector3? push) {
  if (push == null) return Vector3.zero();
  final planar = Vector3(push.x, 0, push.z);
  return planar.length2 < 1e-9 ? Vector3.zero() : (planar..normalize());
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
