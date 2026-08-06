part of '../skills.dart';

void installSkillCasting(GameBuilder game) {
  game
    ..configureEvent<CastLeap>(retainedUpdates: null)
    ..registerComponent<PendingWindBlast>()
    ..world.insert(SkillBook())
    ..addSystem(Schedules.frameStart, buyUpgrades, writes: const {Health})
    ..addSystem(
      Schedules.fixedUpdate,
      castSkills,
      inSet: GameSets.actions,
      reads: const {Player, Enemy, Health, PlayerMotion, SceneTransform},
      writes: const {Knockback, PlayerAnimator},
      runIf: inState(GameStatus.fighting),
    )
    ..addSystem(
      Schedules.fixedUpdate,
      firePendingWindBlast,
      inSet: GameSets.actions,
      reads: const {Player, Enemy, Health, SceneTransform},
      writes: const {PendingWindBlast},
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
    world.query<Health>(require: const [Player]).each((entity, health) {
      health.max += vitalityHealthPerLevel;
      health.current += vitalityHealthPerLevel;
    });
  }
}

void castSkills(World world) {
  final book = world.resource<SkillBook>()..tick(world.dt);
  final row = world
      .query2<PlayerMotion, SceneTransform>(require: const [Player])
      .firstOrNull;
  if (row == null) return;
  final (player, motion, transform) = row;

  for (final cast in world.events<SkillCast>()) {
    if (!book.isReady(cast.skill)) continue;
    book.trigger(cast.skill);
    final power = book.powerOf(cast.skill);
    switch (cast.skill) {
      case Skill.fireGush:
        _castFireGush(world, motion, transform, power);
        world.tryGet<PlayerAnimator>(player)?.playBackwardDash();
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
        // Fire after landing.
        world.add(player, PendingWindBlast(power));
        world.emit(const CastLeap());

      case Skill.shield:
        world.add(player, Barrier(shieldChargesFor(book.levelOf(cast.skill))));
    }
  }
}

void firePendingWindBlast(World world) {
  final row = world
      .query2<PendingWindBlast, SceneTransform>(require: const [Player])
      .firstOrNull;
  if (row == null) return;
  final (player, pending, transform) = row;
  pending.elapsed += world.dt;
  if (pending.elapsed >= windCastSeconds) {
    _castWindBlast(world, transform, pending.power);
    world.remove<PendingWindBlast>(player);
  }
}

void _castFireGush(
  World world,
  PlayerMotion motion,
  SceneTransform origin,
  double power,
) {
  world.query2<Health, SceneTransform>(require: const [Enemy]).each((
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
  world.query2<Health, SceneTransform>(require: const [Enemy]).each((
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
  world.entitiesWith(require: const [LavaPit]).each(world.despawn);
  // The player survives a restart.
  world.entitiesWith(require: const [Player]).each(world.remove<Barrier>);
}
