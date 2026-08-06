part of '../enemies.dart';

void installBrawlBrain(GameBuilder game) {
  game
    ..registerComponent<AggroCoordinator>()
    ..addSystem(
      Schedules.startup,
      spawnEnemies,
      writes: const {Enemy, Health, Brawler, AggroCoordinator},
    )
    ..addSystem(
      OnEnter(GameStatus.fighting),
      resetEncounter,
      writes: const {AggroCoordinator},
      runIf: freshRun,
    )
    ..addSystem(
      Schedules.fixedUpdate,
      brawlerDriver,
      inSet: GameSets.actions,
      reads: const {Player, Enemy, Health, SceneTransform},
      writes: const {Brawler},
      runIf: inState(GameStatus.fighting),
    )
    ..addSystem(
      Schedules.fixedUpdate,
      coordinateAggro,
      inSet: GameSets.actions,
      reads: const {Player, Enemy, Health, SceneTransform},
      writes: const {AggroCoordinator, Brawler},
      after: const [brawlerDriver],
      runIf: inState(GameStatus.fighting),
    );
}

void spawnEnemies(World world) {
  world.spawn([AggroCoordinator()]);
}

void resetEncounter(World world) {
  final coordinator = world.query<AggroCoordinator>().firstOrNull?.$2;
  if (coordinator == null) return;
  coordinator
    ..holder = null
    ..cooldown = 0;
}

void brawlerDriver(World world) {
  final player = world
      .query<SceneTransform>(require: const [Player])
      .firstOrNull
      ?.$2;
  if (player == null) return;
  final windup = world.events<PlayerWindup>().lastOrNull;

  world.query3<Brawler, Health, SceneTransform>(require: const [Enemy]).each((
    entity,
    brawler,
    health,
    transform,
  ) {
    final phase = brawler.phase;
    brawler
      ..sinceHurt += world.dt
      ..sinceDodge += world.dt;
    phase.tick(world.dt);

    if (!health.alive) {
      if (phase.state != BrawlPhase.dying) phase.go(BrawlPhase.dying);
      return;
    }
    if (phase.state == BrawlPhase.dying ||
        world.expiryOf<Transforming>(entity) != null) {
      return;
    }
    if (world.tryGet<Knockback>(entity)?.incapacitated ?? false) {
      if (phase.state != BrawlPhase.staggered) phase.go(BrawlPhase.staggered);
      return;
    }

    final distance = planarDistance(transform, player);
    switch (phase.state) {
      case BrawlPhase.rising:
        _advanceAfter(brawler, risingSeconds, BrawlPhase.approach);
      case BrawlPhase.approach:
        if (distance <= engageRange) phase.go(BrawlPhase.circle);
      case BrawlPhase.circle:
        _driveCircle(brawler, transform, player, windup, distance, world.dt);
      case BrawlPhase.taunting:
        _advanceAfter(brawler, tauntSeconds, BrawlPhase.circle);
      case BrawlPhase.telegraph:
        _advanceAfter(
          brawler,
          brawler.windup / brawler.tempo,
          BrawlPhase.swing,
        );
      case BrawlPhase.swing:
        _advanceAfter(
          brawler,
          swingSeconds / brawler.tempo,
          BrawlPhase.recover,
        );
      case BrawlPhase.recover:
        _driveRecovery(brawler);
      case BrawlPhase.dodging:
        _advanceAfter(brawler, dodgeSeconds, BrawlPhase.circle);
      case BrawlPhase.staggered:
        _advanceAfter(brawler, brawlStaggerSeconds, BrawlPhase.circle);
      case BrawlPhase.dying:
        break;
    }
  });
}

void _driveCircle(
  Brawler brawler,
  SceneTransform transform,
  SceneTransform player,
  PlayerWindup? windup,
  double distance,
  double dt,
) {
  brawler.sinceTaunt += dt;
  if (_shouldDodge(brawler, transform, player, windup)) {
    brawler
      ..sinceDodge = 0
      ..dodgeSign = brawler.circleDirection >= 0 ? 1 : -1;
    brawler.phase.go(BrawlPhase.dodging);
    return;
  }
  if (brawler.hasToken && distance <= brawlerAttackRange) {
    final roll = (brawler.wobbleSeed * 7.31 + brawler.wobble * 1.7) % 1.0;
    final combo = roll < (brawler.giant ? giantComboChance : comboChance);
    brawler.comboLeft = combo ? 1 : 0;
    _beginChop(brawler, combo ? comboOpenerSeconds : telegraphSeconds);
    return;
  }
  if (distance > engageRange * 1.8) {
    brawler.phase.go(BrawlPhase.approach);
    return;
  }
  final tauntAt = tauntIntervalSeconds + brawler.wobbleSeed.remainder(3.0);
  if (!brawler.hasToken && brawler.sinceTaunt >= tauntAt) {
    brawler.sinceTaunt = 0;
    brawler.phase.go(BrawlPhase.taunting);
  }
}

bool _shouldDodge(
  Brawler brawler,
  SceneTransform transform,
  SceneTransform player,
  PlayerWindup? windup,
) {
  if (windup == null || brawler.sinceDodge < dodgeCooldownSeconds) {
    return false;
  }
  final roll = (brawler.wobbleSeed * 3.7 + brawler.wobble * 2.3) % 1.0;
  return roll < dodgeChance &&
      withinArc(
        from: player,
        facing: windup.facing,
        to: transform,
        reach: dodgeThreatRange,
        halfArc: dodgeThreatHalfArc,
      );
}

void _driveRecovery(Brawler brawler) {
  final linking = brawler.comboLeft > 0;
  final window = linking ? comboLinkSeconds : recoverSeconds;
  if (brawler.phase.elapsed < window / brawler.tempo) return;
  if (!linking) {
    brawler.phase.go(BrawlPhase.circle);
    return;
  }
  brawler.comboLeft--;
  _beginChop(brawler, comboFollowSeconds);
}

void _advanceAfter(Brawler brawler, double seconds, BrawlPhase next) {
  if (brawler.phase.elapsed >= seconds) brawler.phase.go(next);
}

void _beginChop(Brawler brawler, double windup) {
  brawler
    ..windup = windup
    ..chopIndex += 1;
  brawler.phase.go(BrawlPhase.telegraph);
}

void coordinateAggro(World world) {
  final coordinator = world.query<AggroCoordinator>().firstOrNull?.$2;
  if (coordinator == null) return;

  _releaseAggro(world, coordinator);
  _grantAggro(world, coordinator);
  _syncAggro(world, coordinator.holder);
}

void _releaseAggro(World world, AggroCoordinator coordinator) {
  final holder = coordinator.holder;
  if (holder == null) return;
  final brawler = world.tryGet<Brawler>(holder);
  final health = world.tryGet<Health>(holder);
  if (brawler != null &&
      health != null &&
      health.alive &&
      brawler.phase.state != BrawlPhase.dying &&
      brawler.phase.state != BrawlPhase.staggered &&
      (brawler.phase.state != BrawlPhase.recover || brawler.comboLeft > 0)) {
    return;
  }
  coordinator
    ..holder = null
    ..cooldown = aggroCooldownSeconds;
}

void _grantAggro(World world, AggroCoordinator coordinator) {
  if (coordinator.holder != null) return;
  coordinator.cooldown -= world.dt;
  if (coordinator.cooldown > 0) return;
  final player = world
      .query<SceneTransform>(require: const [Player])
      .firstOrNull
      ?.$2;
  if (player == null) return;
  coordinator.holder = _nearestAttacker(world, player);
}

Entity? _nearestAttacker(World world, SceneTransform player) {
  Entity? nearest;
  var nearestDistance = double.infinity;
  world.query3<Brawler, Health, SceneTransform>(require: const [Enemy]).each((
    entity,
    brawler,
    health,
    transform,
  ) {
    if (!health.alive || brawler.phase.state != BrawlPhase.circle) return;
    final dx = player.translation.x - transform.translation.x;
    final dz = player.translation.z - transform.translation.z;
    final distance = dx * dx + dz * dz;
    if (distance >= nearestDistance) return;
    nearest = entity;
    nearestDistance = distance;
  });
  return nearest;
}

void _syncAggro(World world, Entity? holder) {
  world.query<Brawler>(require: const [Enemy]).each((entity, brawler) {
    brawler.hasToken = entity == holder;
  });
}
