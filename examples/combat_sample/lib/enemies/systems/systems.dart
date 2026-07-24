part of '../enemies.dart';

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

/// Attaches an enemy model or fallback capsule.
void attachEnemyVisuals(World world) {
  final hasCharacters = world.hasResource<CharacterAssets>();
  world.entitiesWith(require: const [Enemy]).each((enemy) {
    if (world.tryGet<SceneNode>(enemy) != null) return;
    final assets = hasCharacters ? world.resource<CharacterAssets>() : null;
    final brawler = world.tryGet<Brawler>(enemy);
    final lent = assets?.takeBarbarian();
    if (assets != null && lent != null) {
      final model = assets.barbarians[lent];
      final bodyScale =
          characterScale * (brawler?.giant ?? false ? giantScale : 1.0);
      final axe = assets.axe;
      Node? mountedAxe;
      if (axe != null) {
        mountedAxe = axe.clone();
        model.getChildByName('handslot.r')?.add(mountedAxe);
      }
      final wrapper = Node(
        name: 'enemy-model',
        localTransform: Matrix4.compose(
          Vector3.zero(),
          Quaternion.axisAngle(Vector3(0, 1, 0), characterModelYaw),
          Vector3.all(bodyScale),
        ),
      )..add(model);
      final root = Node(name: 'enemy')..add(wrapper);
      _attachHealthBar(world, enemy, root, giant: brawler?.giant ?? false);
      world.add(enemy, SceneNode(root));
      world.add(enemy, buildEnemyAnimator(assets, model));
      world.add(enemy, BrawlerVisuals(bodyRoot: wrapper));
      world.add(enemy, ModelSlot(lent, axe: mountedAxe));
      return;
    }
    final material = PhysicallyBasedMaterial()
      ..baseColorFactor = Vector4(0.72, 0.26, 0.2, 1)
      ..roughnessFactor = 0.65;
    final body =
        Node(
            localTransform: Matrix4.translation(
              Vector3(0, enemyCapsuleHeight / 2 + enemyCapsuleRadius, 0),
            ),
          )
          ..mesh = Mesh(
            CapsuleGeometry(
              radius: enemyCapsuleRadius,
              height: enemyCapsuleHeight,
            ),
            material,
          );
    final root = Node(name: 'enemy')..add(body);
    _attachHealthBar(world, enemy, root, giant: brawler?.giant ?? false);
    world.add(enemy, SceneNode(root));
    world.add(enemy, BrawlerVisuals(bodyRoot: body, capsuleMaterial: material));
  });
}

/// Attaches an enemy health bar.
void _attachHealthBar(
  World world,
  Entity enemy,
  Node root, {
  bool giant = false,
}) {
  final fraction = ValueNotifier<double>(1);
  final barNode =
      Node(
        name: 'health-bar',
        localTransform: Matrix4.translation(
          Vector3(0, healthBarHeight * (giant ? giantScale : 1.0), 0),
        ),
      )..addComponent(
        WidgetComponent(
          child: HealthBarWidget(fraction: fraction),
          size: const Size(240, 64),
          worldHeight: healthBarWorldHeight,
          pixelRatio: 1.5,
          input: WidgetInput.manual,
        ),
      );
  root.add(barNode);
  world.add(enemy, EnemyHealthBar(fraction: fraction, node: barNode));
}

/// Updates enemy health bars.
void updateHealthBars(World world) {
  final rig = world.resource<CameraRig>();
  world.query3<Brawler, Health, EnemyHealthBar>(require: const [Enemy]).each((
    enemy,
    brawler,
    health,
    bar,
  ) {
    final alive = health.alive && brawler.phase.state != BrawlPhase.dying;
    bar.node.visible = alive;
    if (!alive) return;
    final fraction = (health.current / health.max).clamp(0.0, 1.0);
    if (fraction < bar.lastFraction - 1e-4) bar.sinceHit = 0;
    bar.lastFraction = fraction;
    bar.fraction.value = fraction;
    bar.sinceHit += world.dt;

    final transform = world.tryGet<SceneTransform>(enemy);
    if (transform == null) return;
    final cameraYaw = math.atan2(
      rig.position.x - transform.translation.x,
      rig.position.z - transform.translation.z,
    );

    var scale = 1.0;
    var roll = 0.0;
    if (bar.sinceHit < healthBarShakeSeconds) {
      final p = bar.sinceHit / healthBarShakeSeconds;
      final decay = 1 - p;
      scale = 1 + healthBarShakePop * decay;
      roll = healthBarShakeTilt * math.sin(p * math.pi * 3) * decay;
    }
    // Rebuilt in place on the node's own matrix: this runs per enemy per
    // frame, so it must not allocate (no compose, no fresh quaternions).
    // The lift is reapplied every frame — the giant's bar sinks back onto
    // normal height otherwise — and T·Ry·Rz·S mirrors the old compose.
    final barTransform = bar.node.localTransform
      ..setIdentity()
      ..setTranslationRaw(
        0,
        healthBarHeight * (brawler.giant ? giantScale : 1.0),
        0,
      )
      ..rotateY(cameraYaw - brawler.facing);
    if (roll != 0) barTransform.rotateZ(roll);
    if (scale != 1) barTransform.scaleByDouble(scale, scale, scale, 1);
    bar.node.localTransform = barTransform;
  });
}

/// Returns a despawned enemy model to the pool.
void releaseEnemyModel(World world, Entity entity, ModelSlot slot) {
  if (!world.hasResource<CharacterAssets>()) return;
  slot.axe?.detach();
  world.resource<CharacterAssets>().releaseBarbarian(slot.index);
}

/// Render-side consumer of the brawl machine + velocity.
void updateEnemyAnimation(World world) {
  final dt = world.dt;
  world.query2<Brawler, EnemyAnimator>(require: const [Enemy]).each((
    enemy,
    brawler,
    animator,
  ) {
    animator.update(
      brawler,
      dt,
      transforming: world.expiryOf<Transforming>(enemy) != null,
    );
  });
}

/// The giant's growth: while the `Transforming` clock runs, the body
/// swells from normal size to its giant base scale. The clip and the
/// scale share the same clock, so they finish together.
void updateGiantGrowth(World world) {
  world.query2<Brawler, BrawlerVisuals>(require: const [Enemy]).each((
    enemy,
    brawler,
    visuals,
  ) {
    if (!brawler.giant) return;
    final remaining = world.expiryOf<Transforming>(enemy);
    if (remaining == null) return; // done: the base transform IS giant
    final progress = (1 - remaining / giantTransformSeconds)
        .clamp(0.0, 1.0)
        .toDouble();
    // Start at normal size (1 / giantScale of the giant base) and swell.
    final factor = (1 / giantScale) + (1 - 1 / giantScale) * progress;
    visuals.applyGrowth(factor);
  });
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

  world.query3<Brawler, Health, SceneTransform>(require: const [Enemy]).each((
    entity,
    brawler,
    health,
    transform,
  ) {
    brawler.sinceHurt += world.dt; // ages the fire/lava flinch (render-only)
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
        if (brawler.hasToken && distance <= brawlerAttackRange) {
          phase.go(BrawlPhase.telegraph);
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
        if (phase.elapsed >= telegraphSeconds) phase.go(BrawlPhase.swing);
      case BrawlPhase.swing:
        if (phase.elapsed >= swingSeconds) phase.go(BrawlPhase.recover);
      case BrawlPhase.recover:
        if (phase.elapsed >= recoverSeconds) phase.go(BrawlPhase.circle);
      case BrawlPhase.staggered:
        if (phase.elapsed >= brawlStaggerSeconds) phase.go(BrawlPhase.circle);
      case BrawlPhase.dying:
        break; // terminal; DespawnAfter owns the removal
    }
  });
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
        brawler.phase.state == BrawlPhase.recover ||
        brawler.phase.state == BrawlPhase.staggered;
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

/// Barbarian locomotion, one fixed step at a time: approach closes in,
/// circle orbits at a breathing radius, everything from the telegraph on
/// is rooted (facing frozen from the swing so rolls beat committed arcs).
/// A dying body is handed to [_driveCorpse]; the living walk through
/// [_steer] → integrate → [_advanceTumble] → [_applyFacingAndTumble].
void moveBrawlers(World world) {
  final playerRow = world
      .query<SceneTransform>(require: const [Player])
      .firstOrNull;
  if (playerRow == null) return;
  final playerPosition = playerRow.$2.translation;
  final dt = world.dt;

  world.query2<Brawler, SceneTransform>(require: const [Enemy]).each((
    entity,
    brawler,
    transform,
  ) {
    if (brawler.phase.state == BrawlPhase.dying) {
      _driveCorpse(world, entity, brawler, transform, dt);
      return;
    }
    if (world.expiryOf<Transforming>(entity) != null) {
      brawler.velocity.setZero();
      return;
    }

    final (velocityX, velocityZ) = _steer(
      brawler,
      transform,
      playerPosition,
      dt,
      mired: world.has<Mired>(entity),
    );
    brawler.velocity.setValues(velocityX, 0, velocityZ);

    final knockback = world.tryGet<Knockback>(entity);
    // Sent flying (a wind blast): the arc owns them until they land.
    if (knockback == null || !knockback.airborne) {
      transform.translation
        ..x += velocityX * dt
        ..z += velocityZ * dt;
    }
    if (knockback != null) {
      knockback.step(dt, transform.translation);
    } else {
      transform.translation.y = 0;
    }
    clampToArena(transform.translation);

    _advanceTumble(brawler, knockback, dt, corpse: false);
    brawler.downed = knockback?.incapacitated ?? false;
    brawler.airborne = knockback?.airborne ?? false; // falls vs lies
    _applyFacingAndTumble(brawler, transform, sign: 1);
  });
}

/// The living brawler's per-phase steering: ground velocity out, facing
/// written in place. Everything from the telegraph on is rooted.
(double, double) _steer(
  Brawler brawler,
  SceneTransform transform,
  Vector3 playerPosition,
  double dt, {
  required bool mired,
}) {
  final dx = playerPosition.x - transform.translation.x;
  final dz = playerPosition.z - transform.translation.z;
  final distance = math.sqrt(dx * dx + dz * dz).clamp(1e-6, double.infinity);
  final towardX = dx / distance;
  final towardZ = dz / distance;

  var velocityX = 0.0;
  var velocityZ = 0.0;
  switch (brawler.phase.state) {
    case BrawlPhase.approach:
      velocityX = towardX * approachSpeed;
      velocityZ = towardZ * approachSpeed;
      brawler.facing = math.atan2(dx, dz);
    case BrawlPhase.circle:
      if (brawler.hasToken) {
        // The token holder closes in to strike range.
        velocityX = towardX * tokenCloseSpeed;
        velocityZ = towardZ * tokenCloseSpeed;
      } else {
        brawler.wobble += dt;
        final radiusTarget =
            circleRadius +
            circleWobbleAmplitude *
                math.sin(
                  brawler.wobbleSeed +
                      brawler.wobble * circleWobbleRate * 2 * math.pi,
                );
        // Tangential orbit plus a radial correction toward the target
        // radius.
        final tangentX = -towardZ * brawler.circleDirection;
        final tangentZ = towardX * brawler.circleDirection;
        final radial = (distance - radiusTarget).clamp(-1.0, 1.0);
        velocityX = tangentX * circleSpeed + towardX * radial * circleSpeed;
        velocityZ = tangentZ * circleSpeed + towardZ * radial * circleSpeed;
      }
      brawler.facing = math.atan2(dx, dz);
    case BrawlPhase.telegraph:
      brawler.facing = math.atan2(dx, dz); // the tell tracks its mark
    case BrawlPhase.taunting:
      brawler.facing = math.atan2(dx, dz); // roots, but taunts at its mark
    case BrawlPhase.rising:
      break; // on the floor hauling itself up; no drift, no aim yet
    case BrawlPhase.swing ||
        BrawlPhase.recover ||
        BrawlPhase.staggered ||
        BrawlPhase.dying:
      break; // rooted, facing frozen
  }

  // Bogged down in a lava pit. Only the ground speed is mired; the
  // facing/aim above stay full, so it still tracks the player as it
  // wades, and a wind blast can still launch it.
  if (mired) {
    velocityX *= miredSpeedFactor;
    velocityZ *= miredSpeedFactor;
  }
  return (velocityX, velocityZ);
}

/// The knockout: launch once on the killing blow, fly the same kinematic
/// arc a live throw uses, stop dead on touchdown, and hold the authored
/// corpse pose until the dissolve takes it.
void _driveCorpse(
  World world,
  Entity entity,
  Brawler brawler,
  SceneTransform transform,
  double dt,
) {
  final knockback = world.tryGet<Knockback>(entity);
  if (knockback == null) return;
  if (!brawler.corpseLaunched) _launchCorpse(brawler, knockback);

  final wasAirborne = knockback.airborne;
  knockback.step(dt, transform.translation);
  if (wasAirborne && !knockback.airborne) {
    // Dead weight stops dead on touchdown — no carry, no skate — and the
    // node's tumble snaps out in the same frame: from here the authored
    // corpse pose owns the lying body (see the animator's dying case),
    // and the impact hides both cuts.
    knockback.velocity.x = 0;
    knockback.velocity.z = 0;
    brawler.tumble = 0;
  }
  // Keep the flags honest while dying: the animator reads them to pick
  // the skydive vs the landed collapse.
  brawler.downed = knockback.incapacitated;
  brawler.airborne = knockback.airborne;

  _advanceTumble(brawler, knockback, dt, corpse: true);
  clampToArena(transform.translation);
  _applyFacingAndTumble(brawler, transform, sign: brawler.corpseTumbleSign);
}

/// The one-shot fling on the killing blow's direction, at its own speed
/// (the stagger shoves are ~3 m/s — a nudge, not a launch). A kill with
/// no shove behind it just hops and crumples in place. Seeded per kill
/// (slot seed + circling time at death): speed, arc height, and a
/// sideways deflection all vary so a crowd of kills sprays instead of
/// repeating, with the odd home run.
void _launchCorpse(Brawler brawler, Knockback knockback) {
  brawler.corpseLaunched = true;
  final seed = brawler.wobbleSeed + brawler.wobble;
  final bigHit = (seed * 3.7) % 1.0 > 0.82;
  final fling = corpseFlingSpeed * (bigHit ? 1.7 : 0.8 + (seed * 7.31) % 0.5);
  final hop = corpseHopSpeed * (bigHit ? 1.3 : 0.85 + (seed * 11.7) % 0.4);
  final spray = ((seed * 5.13) % 0.7) - 0.35;

  var flingX = knockback.velocity.x;
  var flingZ = knockback.velocity.z;
  final shoved = math.sqrt(flingX * flingX + flingZ * flingZ);
  if (shoved > 1e-3) {
    final nx = flingX / shoved;
    final nz = flingZ / shoved;
    final cosS = math.cos(spray);
    final sinS = math.sin(spray);
    flingX = (nx * cosS - nz * sinS) * fling;
    flingZ = (nx * sinS + nz * cosS) * fling;
  }
  brawler.corpseTumbleSign = brawler.tumble == 0 ? corpseTumblePitch : 1;
  knockback.shove(Vector3(flingX, math.max(knockback.velocity.y, hop), flingZ));
}

/// The one-way tip toward prone: seeded per body through the air (a
/// blast throws a crowd, not a formation), a flat settle through the
/// living's downed beat, and the snap back upright once free. A landed
/// corpse holds zero — the authored corpse pose lies the skeleton down,
/// so any node pitch on top would double-rotate it.
void _advanceTumble(
  Brawler brawler,
  Knockback? knockback,
  double dt, {
  required bool corpse,
}) {
  if (knockback != null && knockback.airborne) {
    brawler.tumble = towardProne(
      brawler.tumble,
      dt * (0.75 + brawler.wobbleSeed % 0.5),
      rate: proneSettleRate,
    );
  } else if (!corpse && knockback != null && knockback.downed > 0) {
    brawler.tumble = towardProne(brawler.tumble, dt, rate: proneSettleRate);
  } else {
    brawler.tumble = 0;
  }
}

/// Yaw to the stored facing, then the tumble pitch on top ([sign] flips
/// it backward for the knockout).
void _applyFacingAndTumble(
  Brawler brawler,
  SceneTransform transform, {
  required double sign,
}) {
  transform.rotation.setAxisAngle(_upAxis, brawler.facing);
  if (brawler.tumble != 0) {
    transform.rotation.setFrom(
      transform.rotation *
          Quaternion.axisAngle(_tumbleAxis, sign * brawler.tumble),
    );
  }
}

final Vector3 _upAxis = Vector3(0, 1, 0);

/// Head over heels, not a flat spin.
final Vector3 _tumbleAxis = Vector3(1, 0, 0);

/// Past the corpse delay, `expiryOf<Dissolving>` drives the body's sink
/// into the ground; a transform effect works on any mesh (the authored
/// dissolve `.fmat` did not read on the skinned body). Also ramps the
/// graybox capsule's emissive telegraph tell.
void updateBrawlerMaterials(World world) {
  world.query2<Brawler, BrawlerVisuals>(require: const [Enemy]).each((
    entity,
    brawler,
    visuals,
  ) {
    if (brawler.phase.state == BrawlPhase.dying) {
      final remaining = world.expiryOf<Dissolving>(entity);
      if (remaining == null) {
        // The clock finished: the body is gone. Hide it for the frame or
        // two before the matching `DespawnAfter` takes the entity with it.
        visuals.hide();
        return;
      }
      if (remaining > dissolveSeconds) return; // the corpse delay
      visuals.applyDeath(
        (1 - remaining / dissolveSeconds).clamp(0.0, 1.0),
        deathSinkDepth,
      );
      return;
    }
    final capsuleMaterial = visuals.capsuleMaterial;
    if (capsuleMaterial != null) {
      final tell = brawler.phase.state == BrawlPhase.telegraph
          ? (brawler.phase.elapsed / telegraphSeconds).clamp(0.0, 1.0)
          : 0.0;
      capsuleMaterial.emissiveFactor = Vector4(
        telegraphEmissive.x * tell,
        telegraphEmissive.y * tell,
        telegraphEmissive.z * tell,
        1,
      );
    }
  });
}
