part of '../skills.dart';

void installSkillCasting(GameBuilder game) {
  game
    ..configureEvent<CastLeap>(retainedUpdates: null)
    ..world.insert(SkillBook())
    ..addSystem(Schedules.frameStart, buyUpgrades, writes: const {Health})
    ..addSystem(
      Schedules.fixedUpdate,
      castSkills,
      inSet: GameSets.actions,
      reads: const {Player},
      writes: const {Fighter, PendingCast},
      after: const [fighterDriver, lockOnSystem],
      independentOf: const [
        announceWindup,
        updateBladeTrail,
        updateDashTrail,
        announceShockwave,
      ],
      runIf: inState(GameStatus.fighting),
    )
    ..addSystem(
      Schedules.fixedUpdate,
      releaseCasts,
      inSet: GameSets.actions,
      reads: const {Player, Enemy, Health, PlayerMotion, SceneTransform},
      writes: const {Fighter, Knockback},
      after: const [castSkills],
      independentOf: const [
        announceWindup,
        updateBladeTrail,
        updateDashTrail,
        announceShockwave,
      ],
      runIf: inState(GameStatus.fighting),
    )
    ..addSystem(
      OnEnter(GameStatus.fighting),
      resetSkills,
      reads: const {Player, LavaPit},
      runIf: freshRun,
    );
}

void buyUpgrades(World world) {
  final book = world.resource<SkillBook>();
  final score = world.resource<Score>();

  for (final request in world.events<SkillUpgradeRequested>()) {
    final skill = request.skill;
    if (book.isMaxed(skill)) continue;
    if (!score.spend(book.priceOf(skill))) continue;
    book.upgrade(skill);
  }

  for (final _ in world.events<VitalityRequested>()) {
    if (book.vitalityLevel >= maxVitalityLevel) continue;
    if (!score.spend(vitalityCost(book.vitalityLevel))) continue;
    book.vitalityLevel++;
    world.query<Health>().having<Player>().each((entity, health) {
      health.max += vitalityHealthPerLevel;
      health.current += vitalityHealthPerLevel;
    });
  }
}

void castSkills(World world) {
  final book = world.resource<SkillBook>()..tick(world.dt);
  final row = world.query<Fighter>().having<Player>().firstOrNull;
  if (row == null) return;
  final (player, fighter) = row;

  Skill? fresh;
  for (final cast in world.events<SkillCast>()) {
    if (book.isReady(cast.skill)) fresh = cast.skill;
  }
  final queued = world.tryGet<PendingCast>(player)?.skill;
  final wanted = fresh ?? queued;
  if (wanted == null) return;
  if (!fighter.canAct || !book.isReady(wanted)) {
    if (fresh != null) {
      world.add(player, PendingCast(fresh), removeAfter: skillBufferWindow);
    }
    return;
  }
  if (queued != null) world.remove<PendingCast>(player);
  book.trigger(wanted);
  fighter.beginCast(wanted, castMotionFor(wanted));
  if (wanted == Skill.windBlast) world.emit(const CastLeap());
}

void releaseCasts(World world) {
  final book = world.resource<SkillBook>();
  final row = world
      .query3<Fighter, PlayerMotion, SceneTransform>()
      .having<Player>()
      .firstOrNull;
  if (row == null) return;
  final (player, fighter, motion, transform) = row;
  final skill = fighter.cast;
  if (fighter.phase.state != CombatPhase.casting ||
      fighter.castReleased ||
      skill is! Skill ||
      fighter.phase.elapsed < fighter.castMotion!.release) {
    return;
  }
  fighter.castReleased = true;
  final power = book.powerOf(skill);
  switch (skill) {
    case Skill.fireGush:
      _castFireGush(world, motion, transform, power);
      world
          .tryGet<Knockback>(player)
          ?.shove(
            Vector3(
              -math.sin(motion.facing) * fireGushRecoil,
              0,
              -math.cos(motion.facing) * fireGushRecoil,
            ),
          );
    case Skill.lavaPit:
      _openLavaPit(world, motion, transform, power);
    case Skill.windBlast:
      _castWindBlast(world, transform, power);
    case Skill.shield:
      world.add(player, Barrier(shieldChargesFor(book.levelOf(skill))));
  }
}

void _castFireGush(
  World world,
  PlayerMotion motion,
  SceneTransform origin,
  double power,
) {
  world.query2<Health, SceneTransform>().having<Enemy>().each((
    enemy,
    health,
    at,
  ) {
    if (!health.alive) return;
    if (!withinArc(
      from: origin,
      facing: motion.facing,
      to: at,
      reach: fireGushRange,
      halfArc: fireGushHalfArc,
    )) {
      return;
    }
    world.emit(
      HitLanded(
        enemy,
        fireGushDamage * power,
        knockback: awayFrom(origin, at, fireGushKnockback),
        stagger: false,
      ),
    );
    world.add(enemy, Burning(burnTickDamage * power), removeAfter: burnSeconds);
  });
  final scorchX =
      origin.translation.x + math.sin(motion.facing) * fireGushRange * 0.55;
  final scorchZ =
      origin.translation.z + math.cos(motion.facing) * fireGushRange * 0.55;
  final scorchRadius = fireGushRange * 0.5;
  world.resource<GrassBurns>().scorch(scorchX, scorchZ, scorchRadius);
  spawnScorchEmbers(world, Vector3(scorchX, 0.2, scorchZ), scorchRadius);
  spawnFireGush(
    world,
    Vector3(
      origin.translation.x,
      origin.translation.y + fireGushMuzzleHeight,
      origin.translation.z,
    ),
    motion.facing,
  );
}

void _openLavaPit(
  World world,
  PlayerMotion motion,
  SceneTransform origin,
  double power,
) {
  final x = origin.translation.x + math.sin(motion.facing) * lavaPitDistance;
  final z = origin.translation.z + math.cos(motion.facing) * lavaPitDistance;
  spawnLavaEruption(world, Vector3(x, 0, z));
  world.resource<GrassBurns>().scorch(x, z, lavaPitRadius * 1.15);
  world.spawn([
    LavaPit(lavaTickDamage * power),
    SceneTransform(x, 0, z),
    DespawnAfter(lavaPitSeconds),
  ]);
}

void _castWindBlast(World world, SceneTransform origin, double power) {
  world.query2<Health, SceneTransform>().having<Enemy>().each((
    enemy,
    health,
    at,
  ) {
    if (!health.alive) return;
    if (planarDistance(origin, at) > windBlastRadius) return;
    final push = awayFrom(origin, at, windBlastSpeed * power)
      ..y = windBlastLift * power;
    world.emit(HitLanded(enemy, windBlastDamage * power, knockback: push));
  });
  spawnWindBlast(world, origin.translation.clone());
}

void resetSkills(World world) {
  world.resource<SkillBook>().reset();
  world.entitiesWith<LavaPit>().each(world.despawn);
  // The player survives a restart.
  world.entitiesWith<Player>().each(world.remove<Barrier>);
}
