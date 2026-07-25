part of '../enemies.dart';

/// The barbarian brain: the encounter coordinator, the brawl machine
/// (approach, circle, telegraph, swing, recover, dodge), and the aggro
/// token that keeps one attacker readable at a time.
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

/// Spawns the encounter coordinator.
void spawnEnemies(World world) {
  world.spawn([AggroCoordinator()]);
}

/// Resets encounter coordination for a new run.
void resetEncounter(World world) {
  final coordinator = world.query<AggroCoordinator>().firstOrNull?.$2;
  if (coordinator == null) return;
  coordinator
    ..holder = null
    ..cooldown = 0;
}

/// The brawl machine: approach, circle, (token) telegraph, swing,
/// recover, back to circle; stagger and death arrive via `applyDamage`.
/// Every timing is `phase.elapsed`-driven.
void brawlerDriver(World world) {
  final playerRow = world
      .query<SceneTransform>(require: const [Player])
      .firstOrNull;
  if (playerRow == null) return;
  final playerPosition = playerRow.$2.translation;
  // The tell the pack reads: a windup is committed but has not landed,
  // which is exactly the window a roll beats. It carries the swing's yaw,
  // so only the barbarians actually in the arc react.
  final windup = world.events<PlayerWindup>().lastOrNull;
  final playerTransform = playerRow.$2;

  world.query3<Brawler, Health, SceneTransform>(require: const [Enemy]).each((
    entity,
    brawler,
    health,
    transform,
  ) {
    brawler.sinceHurt += world.dt; // ages the fire/lava flinch (render-only)
    brawler.sinceDodge += world.dt;
    final phase = brawler.phase..tick(world.dt);
    if (!health.alive && phase.state != BrawlPhase.dying) {
      // Killed outside applyDamage (tests, future hazards): still dies.
      phase.go(BrawlPhase.dying);
      return;
    }

    if (phase.state == BrawlPhase.dying) return;
    // Mid-transformation: the giant is busy growing, not fighting.
    if (world.expiryOf<Transforming>(entity) != null) return;

    // Airborne: the throw outlasts the stagger, so without this hold the
    // machine would walk out of `staggered` and start circling and
    // swinging on the way down. It stays staggered until it lands.
    if (world.tryGet<Knockback>(entity)?.incapacitated ?? false) {
      if (phase.state != BrawlPhase.staggered) {
        phase.go(BrawlPhase.staggered);
      }
      return;
    }
    final dx = playerPosition.x - transform.translation.x;
    final dz = playerPosition.z - transform.translation.z;
    final distance = math.sqrt(dx * dx + dz * dz);

    switch (phase.state) {
      case BrawlPhase.rising:
        // Held still by moveBrawlers; the awaken clip plays over this.
        if (phase.elapsed >= risingSeconds) phase.go(BrawlPhase.approach);
      case BrawlPhase.approach:
        if (distance <= engageRange) phase.go(BrawlPhase.circle);
      case BrawlPhase.circle:
        brawler.sinceTaunt += world.dt;
        if (windup != null &&
            withinArc(
              from: playerTransform,
              facing: windup.facing,
              to: transform,
              reach: dodgeThreatRange,
              halfArc: dodgeThreatHalfArc,
            ) &&
            brawler.sinceDodge >= dodgeCooldownSeconds &&
            (brawler.wobbleSeed * 3.7 + brawler.wobble * 2.3) % 1.0 <
                dodgeChance) {
          brawler
            ..sinceDodge = 0
            // Rolls the way it was already orbiting, so the sidestep
            // continues its momentum instead of reversing on the spot.
            ..dodgeSign = brawler.circleDirection >= 0 ? 1 : -1;
          phase.go(BrawlPhase.dodging);
        } else if (brawler.hasToken && distance <= brawlerAttackRange) {
          // Seeded off the circling clock, so the same barbarian does not
          // always pick the same opener.
          final roll = (brawler.wobbleSeed * 7.31 + brawler.wobble * 1.7) % 1.0;
          final combo = roll < (brawler.giant ? giantComboChance : comboChance);
          brawler.comboLeft = combo ? 1 : 0;
          _beginChop(brawler, combo ? comboOpenerSeconds : telegraphSeconds);
        } else if (distance > engageRange * 1.8) {
          phase.go(BrawlPhase.approach);
        } else if (!brawler.hasToken &&
            brawler.sinceTaunt >=
                tauntIntervalSeconds + brawler.wobbleSeed.remainder(3.0)) {
          // Not its turn: heckle. Only a token-less circler taunts, so the
          // attacker's rhythm is never interrupted.
          brawler.sinceTaunt = 0;
          phase.go(BrawlPhase.taunting);
        }
      case BrawlPhase.taunting:
        if (phase.elapsed >= tauntSeconds) phase.go(BrawlPhase.circle);
      case BrawlPhase.telegraph:
        if (phase.elapsed >= brawler.windup / brawler.tempo) {
          phase.go(BrawlPhase.swing);
        }
      case BrawlPhase.swing:
        if (phase.elapsed >= swingSeconds / brawler.tempo) {
          phase.go(BrawlPhase.recover);
        }
      case BrawlPhase.recover:
        // Mid-combo the recover is only a link: it runs short and feeds
        // straight back into the next windup.
        final linking = brawler.comboLeft > 0;
        final window = (linking ? comboLinkSeconds : recoverSeconds);
        if (phase.elapsed >= window / brawler.tempo) {
          if (linking) {
            brawler.comboLeft--;
            _beginChop(brawler, comboFollowSeconds);
          } else {
            phase.go(BrawlPhase.circle);
          }
        }
      case BrawlPhase.dodging:
        if (phase.elapsed >= dodgeSeconds) phase.go(BrawlPhase.circle);
      case BrawlPhase.staggered:
        if (phase.elapsed >= brawlStaggerSeconds) phase.go(BrawlPhase.circle);
      case BrawlPhase.dying:
        break; // terminal; DespawnAfter owns the removal
    }
  });
}

/// Starts a chop's windup at [windup]. Bumping the counter is what makes
/// the mapper replay the clip: a combo's follow-up re-enters `telegraph`
/// without the animation ever leaving the attack pose.
void _beginChop(Brawler brawler, double windup) {
  brawler
    ..windup = windup
    ..chopIndex += 1;
  brawler.phase.go(BrawlPhase.telegraph);
}

/// The aggro token: one holder at a time. Returned on the holder's
/// recover/stagger entry or death, with a cooldown before the next grant;
/// granted to the nearest circling, living barbarian. Only the holder may
/// enter telegraph; everyone else keeps circling.
void coordinateAggro(World world) {
  final coordinator = world.query<AggroCoordinator>().firstOrNull?.$2;
  if (coordinator == null) return;

  final holder = coordinator.holder;
  if (holder != null) {
    final brawler = world.tryGet<Brawler>(holder);
    final health = world.tryGet<Health>(holder);
    // State-based, not edge-based: applyDamage staggers in the resolution
    // set, whose edges the next driver tick lowers before this runs.
    final done =
        brawler == null ||
        health == null ||
        !health.alive ||
        brawler.phase.state == BrawlPhase.dying ||
        brawler.phase.state == BrawlPhase.staggered ||
        // A combo keeps the token across its link recover, so a fresh
        // grant cannot cut the follow-up chop off.
        (brawler.phase.state == BrawlPhase.recover && brawler.comboLeft == 0);
    if (done) {
      coordinator.holder = null;
      coordinator.cooldown = aggroCooldownSeconds;
    }
  }

  if (coordinator.holder == null) {
    coordinator.cooldown -= world.dt;
    if (coordinator.cooldown <= 0) {
      final playerRow = world
          .query<SceneTransform>(require: const [Player])
          .firstOrNull;
      if (playerRow != null) {
        final playerPosition = playerRow.$2.translation;
        Entity? nearest;
        var nearestDistance = double.infinity;
        world
            .query3<Brawler, Health, SceneTransform>(require: const [Enemy])
            .each((entity, brawler, health, transform) {
              if (!health.alive || brawler.phase.state != BrawlPhase.circle) {
                return;
              }
              final dx = playerPosition.x - transform.translation.x;
              final dz = playerPosition.z - transform.translation.z;
              final distance = dx * dx + dz * dz;
              if (distance < nearestDistance) {
                nearestDistance = distance;
                nearest = entity;
              }
            });
        coordinator.holder = nearest;
      }
    }
  }

  // Mirror the grant onto the brawlers every tick: this system is the
  // flag's single writer, and a stale flag on a released brawler would
  // let two attack at once.
  final granted = coordinator.holder;
  world.query<Brawler>(require: const [Enemy]).each((entity, brawler) {
    brawler.hasToken = entity == granted;
  });
}
