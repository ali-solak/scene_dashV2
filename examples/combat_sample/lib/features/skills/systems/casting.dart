part of '../skills.dart';

/// Casting: the upgrade purchases, the cast dispatch, the deferred wind
/// blast, and the per-run reset.
void installSkillCasting(GameBuilder game) {
  game
    // The leap is consumed by the next fixed step.
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

/// Serves the menu's purchases (frameStart, so it works while the menu
/// has the world paused). A buy that cannot be afforded is simply
/// ignored; the menu greys those out, this is the authority.
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
    // The point of the buy: a taller bar, and the difference handed over
    // now rather than at the next wave.
    world.query<Health>(require: const [Player]).each((entity, health) {
      health.max += vitalityHealthPerLevel;
      health.current += vitalityHealthPerLevel;
    });
  }
}

/// Runs the cooldowns down and serves every [SkillCast] the player can
/// actually pay for. Casting is instant: these are panic buttons and
/// openers, not another attack machine to time.
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
    // Every skill scales off its own level; the authored numbers are
    // level 1, so this is 1.0 on a fresh purchase.
    final power = book.powerOf(cast.skill);
    switch (cast.skill) {
      case Skill.fireGush:
        _castFireGush(world, motion, transform, power);
        // Muzzle recoil: a firm shove backward (opposite the cone's facing),
        // so the gush kicks. A decaying knockback, like a slight roll-back.
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
        // The player leaps NOW; the gust itself waits for the landing (see
        // firePendingWindBlast), so it reads as thrown down on impact. The
        // cost and cooldown still commit on the button.
        world.add(player, PendingWindBlast(power));
        world.emit(const CastLeap());

      case Skill.shield:
        _raiseBarrier(world, player, book.levelOf(cast.skill));
    }
  }
}

/// Unleashes a wind gust once its leap has landed: fires the
/// [PendingWindBlast] `castSkills` armed at [windCastSeconds] (the leap's
/// flight time), from wherever the fighter came down.
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

/// Raises the barrier. Charges come from the level, not `powerOf`: this
/// skill scales by a count, and a fractional block is not a thing.
/// Re-adding replaces, so a cast while one is up refreshes it to full.
void _raiseBarrier(World world, Entity player, int level) {
  world.add(player, Barrier(shieldChargesFor(level)));
}

/// A cone of flame: everything inside takes the hit and catches fire.
/// The shove is small; this is not a knockback tool, and stacking it
/// with the burn's ticks would drag the pack out of your reach.
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
        // A gush is not a hammer: it burns, it does not interrupt.
        stagger: false,
      ),
    );
    // Re-applying refreshes the clock instead of stacking a second fire.
    world.add(enemy, Burning(burnTickDamage * power), removeAfter: burnSeconds);
  });
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

/// Opens a pool of lava on the ground ahead of the player. The pit is its
/// own entity with its own lifetime; the cast is over the instant it
/// lands, the pit is not.
void _openLavaPit(
  World world,
  PlayerMotion motion,
  SceneTransform origin,
  double power,
) {
  final x = origin.translation.x + math.sin(motion.facing) * lavaPitDistance;
  final z = origin.translation.z + math.cos(motion.facing) * lavaPitDistance;
  // The ground breaking open (a no-op headless), so the pit arrives
  // instead of simply being switched on.
  spawnLavaEruption(world, Vector3(x, 0, z));
  world.spawn([
    LavaPit(lavaTickDamage * power),
    SceneTransform(x, 0, z),
    // The pit's own clock is its whole lifetime. No DespawnOnExit:
    // opening the skill menu leaves `fighting`, and a pause must not
    // swallow a pit you already paid for.
    DespawnAfter(lavaPitSeconds),
  ]);
}

/// The panic button: everything in the ring goes up and out. Damage is an
/// afterthought; the launch is the skill, and it rides the same ballistic
/// knockback a giant's blow puts on the player.
void _castWindBlast(World world, SceneTransform origin, double power) {
  world.query2<Health, SceneTransform>(require: const [Enemy]).each((
    enemy,
    health,
    at,
  ) {
    if (!health.alive) return;
    if (planarDistance(origin, at) > windBlastRadius) return;
    // The throw itself gets heavier: further out and higher up, so a
    // levelled blast clears more of the field for longer.
    final push = awayFrom(origin, at, windBlastSpeed * power)
      ..y = windBlastLift * power;
    world.emit(HitLanded(enemy, windBlastDamage * power, knockback: push));
  });
  spawnWindBlast(world, origin.translation.clone());
}

/// `OnEnter(fighting)` behind [freshRun]: a new run starts with nothing
/// bought and nothing on the ground.
void resetSkills(World world) {
  world.resource<SkillBook>().reset();
  world.entitiesWith(require: const [LavaPit]).each(world.despawn);
  // The barrier rides the player, who survives the restart; nothing else
  // would take it back off.
  world.entitiesWith(require: const [Player]).each(world.remove<Barrier>);
}
