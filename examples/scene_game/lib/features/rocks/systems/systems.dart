part of '../rocks.dart';

// Reused scratch so per-rock position reads allocate nothing.
final Vector3 _rockScratch = Vector3.zero();

/// OnEnter(playing): spawn the spawner — a run-scoped process entity.
/// Respawning per run *is* the cadence reset, and `DespawnOnExit` sweeps
/// it with everything else when the run ends.
void spawnRockSpawner(World world) {
  world.spawn([
    const Name('rock-spawner'),
    RockSpawner(),
    const DespawnOnExit(GameStatus.playing),
  ]);
}

/// Drops new rocks at the top of the ramp each fixed step, driven by the
/// run's spawner process entity (absent outside `playing`).
void spawnRocks(World world) {
  final game = world.resource<GameState>();
  world.query<RockSpawner>().each((entity, spawner) {
    final due = spawner.tick(world.dt, survived: game.survived);
    for (var i = 0; i < due; i++) {
      world.spawn(
        rockBundle(
          x: spawner.nextLane(),
          flaming: spawner.nextIsFlaming(game.survived),
        ),
      );
    }
  });
}

/// Feeds the shared flame-trail emitter: rewrites the spawn shape's rock
/// positions from this frame's [Flaming] rocks and scales the spawn rate
/// with their count (zero rocks ⇒ zero rate — outside runs the emitter
/// just idles). The emitter node itself never moves; see [FlameTrailShape]
/// for why that is the crux of the whole effect.
void updateFlameTrails(World world) {
  final trails = world.singleOrNull<FlameTrailEmitter>();
  if (trails == null) return; // Headless: no emitter entity.
  final shape = trails.shape;
  shape.origins.clear();
  world.query<SceneNode>(require: const [Rock, Flaming]).each((
    entity,
    binding,
  ) {
    binding.node.globalTranslationInto(_rockScratch);
    shape.origins
      ..add(_rockScratch.x)
      ..add(_rockScratch.y)
      ..add(_rockScratch.z);
  });
  trails.spawner.rate = (shape.origins.length ~/ 3) * rockTrailEmberRate;
}

/// `observe<RockHitReaction>` onRemove: no reaction ⇒ shell hidden, for
/// *every* removal path — flash finished, rock despawned mid-flash, any
/// future dispel — not just the animator's happy path.
void clearHitShell(World world, Entity entity, RockHitReaction reaction) {
  world.tryGet<RockVisuals>(entity)?.shell.setLocalUniform(0, 0, 0, 0);
}

/// Animates the per-rock flash shell while a hit reaction is active. The
/// component's `removeAfter:` deadline is the whole lifecycle — the
/// framework drops it on schedule and the observer zeroes the shell — so
/// this system only reads the deadline back and shapes the pulse. Only the
/// child shell is scaled — never the physics-driven root node.
void updateRockHitReactions(World world) {
  world.query2<RockHitReaction, RockVisuals>().each((
    entity,
    reaction,
    visuals,
  ) {
    final remaining = world.expiryOf<RockHitReaction>(entity);
    if (remaining == null) {
      return;
    }
    final t = 1 - (remaining / rockHitReactionDuration).clamp(0.0, 1.0);
    final env = math.sin(t * math.pi);
    final pulse = 1 + 0.1 * math.sin(t * math.pi * 4);
    final peak = 1.15 + 0.55 * reaction.strength;
    visuals.shell.setLocalUniform(0, 0, 0, peak * env * pulse);
  });
}
