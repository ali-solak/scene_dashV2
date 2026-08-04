part of '../enemies.dart';

/// Spawns enemy dodge effects.
void spawnBrawlerFx(World world) {
  final playerRow = world
      .query<SceneTransform>(require: const [Player])
      .firstOrNull;
  if (playerRow == null) return;
  final playerPosition = playerRow.$2.translation;

  world.query2<Brawler, SceneTransform>(require: const [Enemy]).each((
    entity,
    brawler,
    transform,
  ) {
    if (!brawler.phase.justEntered(BrawlPhase.dodging)) return;
    final dx = playerPosition.x - transform.translation.x;
    final dz = playerPosition.z - transform.translation.z;
    final distance = math.sqrt(dx * dx + dz * dz).clamp(1e-6, double.infinity);
    final towardX = dx / distance;
    final towardZ = dz / distance;
    spawnDashDust(
      world,
      transform.translation.clone(),
      Vector3(
        -towardX * dodgeBackWeight -
            towardZ * brawler.dodgeSign * dodgeSideWeight,
        0,
        -towardZ * dodgeBackWeight +
            towardX * brawler.dodgeSign * dodgeSideWeight,
      ),
    );
  });
}

/// Everything the barbarian shows: model, health bar, animation mapper,
/// giant growth and death materials.
void installEnemyVisuals(GameBuilder game) {
  game
    ..registerComponent<BrawlerVisuals>()
    ..registerComponent<EnemyAnimator>()
    ..registerComponent<EnemyHealthBar>()
    ..registerComponent<ModelSlot>()
    // Return despawned models to the pool.
    ..observe<ModelSlot>(onRemove: releaseEnemyModel)
    // Attach bodies to new enemies.
    ..addSystem(
      Schedules.update,
      attachEnemyVisuals,
      inSet: GameSets.logic,
      reads: const {Enemy, Brawler},
      runIf: hasResource<Scene>(),
    )
    ..addSystem(
      Schedules.update,
      updateBrawlerMaterials,
      inSet: GameSets.logic,
      reads: const {Enemy, Brawler, Dissolving},
      writes: const {BrawlerVisuals},
      runIf: hasResource<Scene>(),
    )
    ..addSystem(
      Schedules.update,
      updateEnemyAnimation,
      inSet: GameSets.logic,
      reads: const {Enemy, Brawler},
      writes: const {EnemyAnimator},
      runIf: hasResource<Scene>(),
    )
    ..addSystem(
      Schedules.update,
      updateGiantGrowth,
      inSet: GameSets.logic,
      reads: const {Enemy, Brawler, Transforming},
      writes: const {BrawlerVisuals},
      after: const [updateBrawlerMaterials],
      runIf: hasResource<Scene>(),
    )
    // Fixed step, unlike the rest of this group: it rides the brawl
    // machine's entry edge, which is one fixed tick wide.
    ..addSystem(
      Schedules.fixedUpdate,
      spawnBrawlerFx,
      inSet: GameSets.actions,
      reads: const {Player, Enemy, Brawler, SceneTransform},
      // Run after enemy decisions.
      after: const [brawlerDriver, coordinateAggro],
      runIf: hasResource<Scene>(),
    )
    ..addSystem(
      Schedules.update,
      updateHealthBars,
      inSet: GameSets.logic,
      reads: const {Enemy, Brawler, Health, SceneTransform},
      writes: const {EnemyHealthBar},
      runIf: hasResource<Scene>(),
    );
}

/// Attaches an enemy model or fallback capsule.
void attachEnemyVisuals(World world) {
  final hasCharacters = world.hasResource<CharacterAssets>();
  world.entitiesWith(require: const [Enemy]).each((enemy) {
    if (world.tryGet<NodeRef>(enemy) != null) return;
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
      world.add(enemy, NodeRef(root));
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
    world.add(enemy, NodeRef(root));
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
    // Rebuild the health bar transform.
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
