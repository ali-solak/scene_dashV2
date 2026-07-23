part of '../rules.dart';

/// The player is dead when its health hits zero: drop the world into
/// `lost`. `OnEnter(lost)` slows time; the HUD shows the restart prompt.
void checkPlayerDeath(World world) {
  final health = world.query<Health>(require: const [Player]).firstOrNull?.$2;
  if (health != null && !health.alive) {
    world.setState(GameStatus.lost);
  }
}

/// Leaves the title screen (frameStart, alongside the other intents).
/// `resetPending` is already true at boot, so the run starts clean
/// through the same `startRun` path a restart uses.
void requestStart(World world) {
  if (!world.consumeAny<GameStarted>()) return;
  if (world.state<GameStatus>() != GameStatus.title) return;
  world.resource<CameraRig>().intro = introZoomSeconds;
  world.setState(GameStatus.fighting);
}

/// Consumes the restart intent (frameStart, so it never lags the event
/// retention window): while lost, a restart request returns the world to
/// `fighting`; each feature's `OnEnter(fighting)` does the actual reset.
void requestRestart(World world) {
  if (!world.consumeAny<RestartRequested>()) return;
  if (world.state<GameStatus>() != GameStatus.lost) return;
  world.resource<RunControl>().resetPending = true;
  world.setState(GameStatus.fighting);
}

/// Opens and closes the skill menu. The menu is just a state: everything
/// that fights gates on `fighting`, so the world stops the moment it
/// opens and resumes where it was on close. Ignored while lost; the
/// death panel owns that screen.
void toggleSkillMenu(World world) {
  if (!world.consumeAny<SkillMenuToggled>()) return;
  switch (world.state<GameStatus>()) {
    case GameStatus.fighting:
      world.setState(GameStatus.skillMenu);
    case GameStatus.skillMenu:
      world.setState(GameStatus.fighting);
    case GameStatus.lost:
    case GameStatus.title:
      break; // the death panel and the title screen own their screens
  }
}

/// Starts a run clean (`OnEnter(fighting)`: boot and every restart).
/// Undoes the slow-motion scale and drives each feature's reset from this
/// one system; a single writer keeps the conflict detector honest.
void startRun(World world) {
  // Closing the skill menu re-enters `fighting` too, and that is a
  // resume, not a new run.
  final control = world.resource<RunControl>();
  if (!control.resetPending) return;
  control.resetPending = false;

  world.clock.timeScale = 1;
  resetPlayerRun(world);
  resetEncounter(world);
  resetWaves(world);
  resetSkills(world);
}

/// Death drops the world into slow motion behind the restart prompt.
void slowMotionOnLoss(World world) {
  world.clock.timeScale = loseSlowMoTimeScale;
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
        _inArc(
          from: enemyTransform,
          facing: brawler.facing,
          to: playerTransform,
          reach: brawlerReach,
          halfArc: brawlerStrikeHalfArc,
        )) {
      final damage = brawlerDamage * brawler.power;
      final shove = _shove(
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
    if (_inArc(
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
          knockback: _shove(playerTransform, enemyTransform, push),
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
    if (push != null) world.tryGet<Knockback>(hit.target)?.shove(push);

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
      if (hit.impact) _kickCamera(world, hurtCameraKick);
    }

    final brawler = world.tryGet<Brawler>(hit.target);
    if (brawler != null && wasAlive) {
      if (health != null && !health.alive) {
        brawler.phase.go(BrawlPhase.dying);
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

    // Your connects landing on enemies kick the camera; the light kicks
    // too, since without hitstop that little punch is what gives a quick
    // slice some weight.
    if (hit.impact && world.has<Enemy>(hit.target)) {
      _kickCamera(world, hit.heavy ? heavyCameraKick : lightCameraKick);
    }
  }
}

/// Wind dramaturgy: the strength eases toward a gust while the pack
/// circles and toward near-still while one telegraphs (the held breath
/// before a swing). Writes the resource the grass material reads, so
/// neither feature imports the other.
void driveWind(World world) {
  final wind = world.resource<WindState>();
  final dt = world.dt;
  var telegraphing = false;
  var anyLiving = false;
  world.query<Brawler>(require: const [Enemy]).each((entity, brawler) {
    if (brawler.phase.state == BrawlPhase.dying) return;
    anyLiving = true;
    if (brawler.phase.state == BrawlPhase.telegraph) telegraphing = true;
  });
  final target = !anyLiving
      ? 1.0
      : (telegraphing ? windCalmStrength : windGustStrength);
  wind.strength +=
      (target - wind.strength) * (1 - math.exp(-windEaseRate * dt));
}

/// Punches the camera, keeping whatever bigger kick is already riding.
/// Resource-guarded: the headless test suite boots a world with no
/// camera at all, and a hit resolving there must not throw.
void _kickCamera(World world, double amount) {
  if (!world.hasResource<CameraRig>()) return;
  final rig = world.resource<CameraRig>();
  rig.kick = math.max(rig.kick, amount);
}

/// The world-space shove a connect delivers: straight out along
/// attacker → victim, at [speed].
Vector3 _shove(SceneTransform from, SceneTransform to, double speed) {
  final dx = to.translation.x - from.translation.x;
  final dz = to.translation.z - from.translation.z;
  final length = math.sqrt(dx * dx + dz * dz).clamp(1e-6, double.infinity);
  return Vector3(dx / length * speed, 0, dz / length * speed);
}

bool _inArc({
  required SceneTransform from,
  required double facing,
  required SceneTransform to,
  required double reach,
  required double halfArc,
}) {
  final dx = to.translation.x - from.translation.x;
  final dz = to.translation.z - from.translation.z;
  final distance = math.sqrt(dx * dx + dz * dz);
  if (distance > reach) return false;
  final angle = math.atan2(dx, dz);
  var difference = (angle - facing) % (2 * math.pi);
  if (difference > math.pi) difference -= 2 * math.pi;
  if (difference < -math.pi) difference += 2 * math.pi;
  return difference.abs() <= halfArc;
}
