part of '../rocks.dart';

// Shared scratch avoids frame allocations.
final Vector3 _rockScratch = Vector3.zero();

void spawnRockSpawner(World world) {
  world.spawn([
    const Name('rock-spawner'),
    RockSpawner(),
    const DespawnOnExit(GameStatus.playing),
  ]);
}

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

void updateFlameTrails(World world) {
  final trails = world.singleOrNull<FlameTrailEmitter>();
  if (trails == null) return;
  final shape = trails.shape;
  shape.origins.clear();
  world.query<NodeRef>(require: const [Rock, Flaming]).each((entity, binding) {
    binding.node.globalTranslationInto(_rockScratch);
    shape.origins
      ..add(_rockScratch.x)
      ..add(_rockScratch.y)
      ..add(_rockScratch.z);
  });
  trails.spawner.rate = (shape.origins.length ~/ 3) * rockTrailEmberRate;
}

void clearHitShell(World world, Entity entity, RockHitReaction reaction) {
  world.tryGet<RockVisuals>(entity)?.shell.setLocalUniform(0, 0, 0, 0);
}

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
