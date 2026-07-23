part of '../skills.dart';

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

/// `OnEnter(fighting)` behind [freshRun]: a new run starts with nothing
/// bought and nothing on the ground.
void resetSkills(World world) {
  world.resource<SkillBook>().reset();
  world.entitiesWith(require: const [LavaPit]).each(world.despawn);
  // The barrier rides the player, who survives the restart; nothing else
  // would take it back off.
  world.entitiesWith(require: const [Player]).each(world.remove<Barrier>);
}

/// Lights up whoever is burning and puts the fire out when the burn's
/// clock ends (a no-op headless). Driven off the presence of [Burning],
/// so a burn refreshed mid-fire never restarts the flame.
void updateBurnFlames(World world) {
  world.query<SceneNode>(require: const [Enemy]).each((entity, ref) {
    final burning = world.tryGet<Burning>(entity) != null;
    final flame = world.tryGet<BurnFlame>(entity);
    if (burning && flame == null) {
      final node = buildBurnFlame();
      ref.node.add(node);
      world.add(entity, BurnFlame(node));
    } else if (!burning && flame != null) {
      ref.node.remove(flame.node);
      world.remove<BurnFlame>(entity);
    }
  });
}

/// Raises and drops the light sphere (and the arm shield) with the
/// barrier itself, and drives the bubble's brightness from what is left
/// (a no-op headless). Driven off the presence of [Barrier]:
/// `applyDamage` can remove it anywhere, and the bubble must follow.
void updateBarrierVisual(World world) {
  final dt = world.dt;
  world.query<SceneNode>(require: const [Player]).each((entity, ref) {
    final barrier = world.tryGet<Barrier>(entity);
    final visual = world.tryGet<BarrierVisual>(entity);

    if (barrier == null) {
      if (visual == null) return;
      ref.node.remove(visual.sphere);
      // The shield hangs off an animated joint deep in the skeleton, not
      // off the node we added it under; detach is the only way back.
      visual.arm?.detach();
      world.remove<BarrierVisual>(entity);
      return;
    }

    var current = visual;
    if (current == null) {
      final built = buildBarrierSphere(
        radius: shieldRadius,
        height: shieldHeight,
        authored: world.hasResource<WorldAssets>()
            ? world.resource<WorldAssets>().barrierMaterial
            : null,
      );
      ref.node.add(built.node);
      current = BarrierVisual(
        sphere: built.node,
        material: built.material,
        arm: _mountShield(world, ref.node),
      );
      world.add(entity, current);
    }

    current.elapsed += dt;
    setBarrierCharge(
      current.material,
      time: current.elapsed,
      remaining: barrier.charges / barrier.maxCharges,
      // 1 on the frame of a block, decaying to 0 over the flash window.
      // Off the gameplay clock alone: adding this frame's dt would
      // double-count it, and `sinceBlock` starts at infinity so a fresh
      // barrier reads 0 here.
      flash: 1 - barrier.sinceBlock / shieldFlashSeconds,
      hitFrom: barrier.hitFrom,
    );
  });
}

/// Hangs the shield on the character's left hand slot, when there is a
/// character and a shield to hang. A clone per raise: the template is
/// shared, and the barrier can come and go many times in a run.
Node? _mountShield(World world, Node body) {
  if (!world.hasResource<CharacterAssets>()) return null;
  final template = world.resource<CharacterAssets>().shield;
  final slot = body.getChildByName('handslot.l');
  if (template == null || slot == null) return null;
  final shield = template.clone()
    // Stands the slab up and turns its face forward; the hand slot's own
    // frame puts it flat otherwise. See [shieldMountRotation].
    ..localTransform = Matrix4.compose(
      Vector3.zero(),
      shieldMountRotation,
      Vector3.all(1),
    );
  slot.add(shield);
  return shield;
}

/// Gives every fresh pit its crust and its embers (a no-op headless).
void attachLavaVisuals(World world) {
  final assets = world.hasResource<WorldAssets>()
      ? world.resource<WorldAssets>()
      : null;
  world.query2<LavaPit, SceneTransform>().each((entity, pit, at) {
    if (world.tryGet<SceneNode>(entity) != null) return;
    world.add(
      entity,
      SceneNode(
        buildLavaPitNode(
          material: assets?.lavaMaterial,
          center: Vector2(at.translation.x, at.translation.z),
        ),
      ),
    );
  });
}

/// Drives the crust's `time` and its swell-in/cool-down (L3: the material
/// follows the pit's clock, the pit never asks the material anything).
void updateLavaMaterials(World world) {
  world.query2<LavaPit, SceneNode>().each((entity, pit, ref) {
    final remaining = world.expiryOf<DespawnAfter>(entity) ?? lavaPitSeconds;
    // Swells open fast, then dims over its last second as it crusts over.
    final heat =
        (pit.elapsed / lavaPitOpenSeconds).clamp(0.0, 1.0) *
        (remaining / lavaPitCoolSeconds).clamp(0.0, 1.0);
    setLavaPitHeat(ref.node, time: pit.elapsed, heat: heat);
  });
}
