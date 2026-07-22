part of '../enemies.dart';

/// Startup: only the aggro coordinator — the barbarians themselves are
/// fielded by the WAVES feature, which owns how many arrive and how
/// strong they are.
void spawnEnemies(World world) {
  world.spawn([AggroCoordinator()]);
}

/// `OnEnter(fighting)` — boot and every restart: hand the token
/// coordinator a clean slate. The barbarians themselves are cleared and
/// re-fielded by the waves feature (`resetWaves`), so there is nothing to
/// resurrect here.
void resetEncounter(World world) {
  final coordinator = world.query<AggroCoordinator>().firstOrNull?.$2;
  if (coordinator == null) return;
  coordinator
    ..holder = null
    ..cooldown = 0;
}

/// OnEnter(fighting), scene-gated: a Barbarian clone per enemy (clips
/// bound to the clone, mapper attached) — or the reddish capsule with a
/// private emissive material when character assets are absent.
void attachEnemyVisuals(World world) {
  final hasCharacters = world.hasResource<CharacterAssets>();
  world.entitiesWith(require: const [Enemy]).each((enemy) {
    // Already bodied — skip.
    if (world.tryGet<SceneNode>(enemy) != null) return;
    final assets = hasCharacters ? world.resource<CharacterAssets>() : null;
    final brawler = world.tryGet<Brawler>(enemy);
    // Borrow a model from the pool; null means the pool is out and this
    // one fights as a graybox capsule.
    final lent = assets?.takeBarbarian();
    if (assets != null && lent != null) {
      final model = assets.barbarians[lent];
      final bodyScale =
          characterScale * (brawler?.giant ?? false ? giantScale : 1.0);
      // Each instance gets its own axe on the animated hand-slot joint.
      final axe = assets.axe;
      if (axe != null) {
        model.getChildByName('handslot.r')?.add(axe.clone());
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
      world.add(enemy, ModelSlot(lent));
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

/// Builds the billboard health bar as a child node above the head and
/// records the [EnemyHealthBar] the drive/aim system pushes to.
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

/// Task 17: push each barbarian's health fraction into its bar, hide the
/// bar on death, and yaw the bar to face the camera (the parent node
/// carries the barbarian's own facing, so the local yaw cancels it).
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
    // A drop is a hit — kick off the punch. (Healing on the breather lifts
    // it, which must not react.)
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

    // The hit reaction: a scale POP and a slash TILT in the screen plane,
    // both decaying over the window. The tilt rides local Z (which points
    // at the camera after the yaw), so it reads as a diagonal jolt rather
    // than a yaw wobble.
    var scale = 1.0;
    var roll = 0.0;
    if (bar.sinceHit < healthBarShakeSeconds) {
      final p = bar.sinceHit / healthBarShakeSeconds;
      final decay = 1 - p;
      scale = 1 + healthBarShakePop * decay;
      roll = healthBarShakeTilt * math.sin(p * math.pi * 3) * decay;
    }
    var rotation = Quaternion.axisAngle(
      Vector3(0, 1, 0),
      cameraYaw - brawler.facing,
    );
    if (roll != 0) {
      rotation = rotation * Quaternion.axisAngle(Vector3(0, 0, 1), roll);
    }
    bar.node.localTransform = Matrix4.compose(
      // Raised by the giant's scale to clear its taller body (this system
      // rewrites the transform each frame, so the lift set at attach time
      // has to be reapplied here or the bar sinks back onto normal height).
      Vector3(0, healthBarHeight * (brawler.giant ? giantScale : 1.0), 0),
      rotation,
      Vector3.all(scale),
    );
  });
}

/// `observe<ModelSlot>(onRemove:)` — fires when a barbarian despawns:
/// its pooled model goes back so the next wave can borrow it.
void releaseEnemyModel(World world, Entity entity, ModelSlot slot) {
  if (!world.hasResource<CharacterAssets>()) return;
  world.resource<CharacterAssets>().releaseBarbarian(slot.index);
}

/// Death hands the corpse to RAPIER: a dynamic body carrying the killing
/// blow's shove plus a hop and a tumble, with a BOX collider (a vertical
/// capsule settles upright — "stands up"; a box tips and lies). The
/// `PhysicsDriven` tag releases the node from the transform sync, so the
/// simulation owns the fall, and the mapper freezes the skeleton so the
/// physics orientation IS the body's pose. Runs once per death.
void launchRagdolls(World world) {
  world.query3<Brawler, Knockback, SceneNode>(require: const [Enemy]).each((
    enemy,
    brawler,
    knockback,
    ref,
  ) {
    if (brawler.phase.state != BrawlPhase.dying) return;
    if (world.tryGet<Ragdoll>(enemy) != null) return; // already launched

    // The corpse carries the killing blow's shove (a hit flings it off; a
    // burn kill, with no knockback, just drops), plus a hop and a tumble.
    // The sink in `updateBrawlerMaterials` takes it under once it settles.
    final push = knockback.velocity * corpseLaunchFactor;
    final body = RapierRigidBody(
      type: BodyType.dynamic_,
      linearVelocity: Vector3(push.x, corpseHopVelocity, push.z),
      // Tumble about the axis perpendicular to the shove: it pitches over.
      angularVelocity: Vector3(push.z, 0, -push.x)..scale(corpseTumbleFactor),
      linearDamping: corpseLinearDamping,
      angularDamping: corpseAngularDamping,
    );
    final collider = RapierCollider(
      shape: BoxShape(halfExtents: corpseHalfExtents),
      localPose: Matrix4.translation(Vector3(0, corpseHalfExtents.y, 0)),
      collisionLayer: PhysicsLayers.fighter,
    );
    ref.node
      ..addComponent(body)
      ..addComponent(collider);
    world.add(enemy, const PhysicsDriven());
    world.add(enemy, Ragdoll(body: body));
    // NOT frozen here. `updateEnemyAnimation` is registered after this
    // system, so freezing on the frame death starts meant it returned
    // early on `frozen` and the death clip never played a single frame —
    // the corpse was locked into whatever pose it held when it died,
    // usually a half-finished blend. That is the pancaked corpse.
    //
    // The skeleton keeps animating through the fall (limbs going limp
    // while the body tumbles reads fine) and `settleRagdolls` freezes it
    // once the body comes to rest.
  });
}

/// Lets a corpse tumble for [corpseSettleSeconds], then nails it down.
///
/// Damping alone never brings a frictionless body to rest — it decays the
/// velocity toward zero without reaching it, so the corpse keeps creeping
/// for as long as it exists. This ends the simulation instead of trying
/// to slow it further.
void settleRagdolls(World world) {
  final dt = world.dt;
  world.query<Ragdoll>(require: const [Enemy]).each((entity, ragdoll) {
    if (ragdoll.settled) return;
    ragdoll.age += dt;
    if (ragdoll.age < corpseSettleSeconds) return;
    ragdoll.settle();
    // The body has stopped; hold the pose it died in.
    world.tryGet<EnemyAnimator>(entity)?.freeze();
  });
}

/// The barbarian mapper system (task 15): render-side consumer of the
/// brawl machine + velocity.
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

/// The giant's growth (task: "grow with the animation"): while the
/// `Transforming` clock runs, the body swells from normal size to its
/// giant base scale — the framework timer driving the transform clip and
/// the scale from the same clock, so they finish together.
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

/// The brawl machine: approach → circle → (token) telegraph → swing →
/// recover → circle; stagger and death arrive via `applyDamage`. Every
/// timing is `phase.elapsed`-driven (L2).
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
    // Mid-transformation: the giant is busy growing, not fighting.
    if (world.expiryOf<Transforming>(entity) != null) return;

    // AIRBORNE. A wind blast throws a barbarian for well over a second,
    // and the stagger it landed with is half that — so without this the
    // machine walks straight back out of `staggered` and starts
    // circling, telegraphing and swinging on the way down. It is not
    // getting up until it has hit the ground.
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

/// The aggro token (~task 12): one holder at a time. Returned on the
/// holder's recover/stagger entry edge or death, with a cooldown before
/// the next grant; granted to the nearest circling, living barbarian. The
/// token holder may *enter telegraph*; everyone else keeps circling.
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

  // Mirror the grant onto the brawlers EVERY tick — this system is the
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
    final dx = playerPosition.x - transform.translation.x;
    final dz = playerPosition.z - transform.translation.z;
    final distance = math.sqrt(dx * dx + dz * dz).clamp(1e-6, double.infinity);
    final towardX = dx / distance;
    final towardZ = dz / distance;

    // A dying body is frozen where it fell (Rapier owns it); a giant
    // mid-transformation is rooted while it swells.
    if (brawler.phase.state == BrawlPhase.dying) return;
    if (world.expiryOf<Transforming>(entity) != null) {
      brawler.velocity.setZero();
      return;
    }

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
        break; // on the floor hauling itself up — no drift, no aim yet
      case BrawlPhase.swing ||
          BrawlPhase.recover ||
          BrawlPhase.staggered ||
          BrawlPhase.dying:
        break; // rooted, facing frozen
    }

    // Bogged down in a lava pit — a hard slog. Only the ground speed is
    // mired; the facing/aim above stay full, so it still turns to track the
    // player as it wades, and a wind blast can still launch it.
    if (world.has<Mired>(entity)) {
      velocityX *= miredSpeedFactor;
      velocityZ *= miredSpeedFactor;
    }
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

    // Thrown: the body tumbles through the arc and snaps flat on landing.
    // Each barbarian spins at its own rate (off the wobble seed), so a
    // blast throws a crowd rather than a formation.
    if (knockback != null && knockback.airborne) {
      // Tips over ONCE on the way down, at its own rate, rather than
      // spinning: a thrown body turns over and lands on its back. The
      // continuous spin read as a rotating prop, not a person.
      brawler.tumble = _towardProne(
        brawler.tumble,
        dt * (0.75 + brawler.wobbleSeed % 0.5),
      );
    } else if (knockback != null && knockback.downed > 0) {
      // LANDED. Settle flat on the floor and stay there for the whole
      // downed beat, the way the death animation ends up — a body that
      // was just thrown across the clearing should not be standing
      // upright the moment it touches down, waiting to get up.
      brawler.tumble = _towardProne(brawler.tumble, dt);
    } else {
      brawler.tumble = 0;
    }
    brawler.downed = knockback?.incapacitated ?? false;
    brawler.airborne = knockback?.airborne ?? false; // falls vs lies
    transform.rotation.setAxisAngle(_upAxis, brawler.facing);
    if (brawler.tumble != 0) {
      transform.rotation.setFrom(
        transform.rotation * Quaternion.axisAngle(_tumbleAxis, brawler.tumble),
      );
    }
  });
}

/// Eases a tumbling body down onto its back. Fast — this is the flop at
/// the end of the arc, not a lie-down.
double _towardProne(double tumble, double dt) {
  const prone = math.pi / 2;
  final step = proneSettleRate * dt;
  if ((prone - tumble).abs() <= step) return prone;
  return tumble + (prone - tumble).sign * step;
}

final Vector3 _upAxis = Vector3(0, 1, 0);

/// Head over heels, not a flat spin.
final Vector3 _tumbleAxis = Vector3(1, 0, 0);

/// The death effect (L3): once the `removeAfter:` clock enters the death
/// window (after the corpse delay), the body SINKS and SHRINKS into the
/// ground, driven by `expiryOf<Dissolving>` — a transform effect that
/// renders on any mesh (the authored dissolve `.fmat` was not reading on
/// the skinned body). The graybox capsule's telegraph tell stays an
/// emissive ramp on its private material; imported bodies tell through the
/// highlight system.
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
