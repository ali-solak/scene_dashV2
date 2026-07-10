part of '../rocks.dart';

// Reused scratch so per-rock position reads allocate nothing.
final Vector3 _rockScratch = Vector3.zero();

/// Drops new rocks at the top of the ramp each fixed step.
void spawnRocks(World world) {
  final spawner = world.resource<RockSpawner>();
  final game = world.resource<GameState>();
  final due = spawner.tick(world.dt, survived: game.survived);
  for (var i = 0; i < due; i++) {
    world.spawn(
      rockBundle(
        x: spawner.nextLane(),
        flaming: spawner.nextIsFlaming(game.survived),
      ),
    );
  }
}

/// Despawns rocks that have rolled off the bottom into the void —
/// despawning inside `each` is safe by construction (deferred verbs).
void cleanupRocks(World world) {
  world.query<SceneNode>(require: const [Rock]).each((entity, binding) {
    binding.node.globalTranslationInto(_rockScratch);
    if (_rockScratch.y < rockKillY) {
      world.despawn(entity);
    }
  });
}

/// Rocks reset their own spawner cadence when a run (re)starts.
void resetRocksOnRunStart(World world) => world.resource<RockSpawner>().reset();

/// Animates the per-rock flash shell while a hit reaction is active, then
/// drops the component. Only the child shell is scaled — never the
/// physics-driven root node.
void updateRockHitReactions(World world) {
  final dt = world.dt;
  world.query2<RockHitReaction, RockVisuals>().each((
    entity,
    reaction,
    visuals,
  ) {
    reaction.flash.tick(dt);
    final shell = visuals.shell;
    if (reaction.flash.finished) {
      shell.setLocalUniform(0, 0, 0, 0);
      world.remove<RockHitReaction>(entity);
      return;
    }
    final t = reaction.flash.fraction;
    final env = math.sin(t * math.pi);
    final pulse = 1 + 0.1 * math.sin(t * math.pi * 4);
    final peak = 1.15 + 0.55 * reaction.strength;
    shell.setLocalUniform(0, 0, 0, peak * env * pulse);
  });
}

/// Startup: build the shared trail pool. Gated on the scene at
/// registration (`runIf: hasResource<Scene>()`), so headless boots skip it.
void spawnRockTrails(World world) {
  world.resource<RockTrails>().pool = buildFlamePool()
    ..addTo(world.resource<Scene>());
}

/// Lays each flaming rock's trail puffs into the shared instanced pool by
/// enumeration order, then hides the slots freed by despawned rocks. Rocks
/// roll down +Z, so the puffs trail a fixed distance behind in -Z (no
/// per-rock state).
void updateRockTrails(World world) {
  final trails = world.resource<RockTrails>();
  final pool = trails.pool;
  if (pool == null) return;
  final scratch = pool.scratch;
  var slot = 0;

  world.query<SceneNode>(require: const [Rock, Flaming]).eachUntil((
    entity,
    binding,
  ) {
    if (slot + _puffsPerRock > pool.capacity) return false; // pool full
    final m = binding.node.globalTransform;
    for (var i = 0; i < _puffsPerRock; i++) {
      final size = rockRadius * (0.34 - i * 0.07);
      scratch
        ..setIdentity()
        ..setTranslationRaw(
          m[12],
          m[13] + rockRadius * (0.12 + 0.08 * i),
          m[14] - rockRadius * 0.55 * (i + 1),
        )
        ..scaleByDouble(size, size, size, 1);
      pool.mesh.setInstanceTransform(slot, scratch);
      slot++;
    }
    return true;
  });

  // Hide instances that belonged to rocks which despawned since last frame.
  for (var i = slot; i < trails.activeCount; i++) {
    pool.hide(i);
  }
  trails.activeCount = slot;
}
