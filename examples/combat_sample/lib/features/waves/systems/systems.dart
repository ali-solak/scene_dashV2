part of '../waves.dart';

/// Walks the director through [endlessRun].
void advanceWaves(World world) {
  final waves = world.resource<WaveState>();
  final routine = waves.routine;

  routine.advance(world.dt, (step) => switch (step) {
    HealPlayer() => _healPlayer(world),
    FieldWave() => _fieldWave(world, waves),
    UntilEngaged() =>
      _livingEnemies(world) > 0 ? StepResult.success : StepResult.running,
    UntilCleared() =>
      _livingEnemies(world) == 0 ? StepResult.success : StepResult.running,
    Breather(:final seconds) =>
      routine.elapsed >= seconds ? StepResult.success : StepResult.running,
  });

  // What the HUD reads.
  waves.intermission = switch (routine.current) {
    Breather(:final seconds) => seconds - routine.elapsed,
    _ => 0,
  };
}

StepResult _healPlayer(World world) {
  world.query<Health>(require: const [Player]).each((entity, health) {
    health.heal(health.max * waveHealFraction);
  });
  return StepResult.success;
}

int _livingEnemies(World world) {
  var living = 0;
  world.query2<Brawler, Health>(require: const [Enemy]).each((
    entity,
    brawler,
    health,
  ) {
    if (health.alive && brawler.phase.state != BrawlPhase.dying) living++;
  });
  return living;
}

StepResult _fieldWave(World world, WaveState waves) {
  final wave = waves.wave += 1;
  final count = enemiesForWave(wave);
  final health = healthForWave(wave);
  final power = powerForWave(wave);
  final tempo = tempoForWave(wave);
  final giantIndex = waveHasGiant(wave) ? wave % count : -1;

  for (var i = 0; i < count; i++) {
    final theta = (i + 0.5) * (2 * math.pi / count) + wave * 0.6;
    final giant = i == giantIndex;
    final entity = world.spawn(
      enemyBundle(
        math.sin(theta) * waveSpawnRadius,
        math.cos(theta) * waveSpawnRadius,
        index: i,
        health: giant ? health * giantHealthFactor : health,
        power: giant ? power * giantPower : power,
        // Giants keep the wave tempo.
        tempo: giant ? 1 : tempo,
        giant: giant,
      ),
    );
    if (giant) {
      world.add(
        entity,
        const Transforming(),
        removeAfter: giantTransformSeconds,
      );
    }
  }
  return StepResult.success;
}

void resetWaves(World world) {
  world.resource<WaveState>().reset();
  world.resource<Score>().reset();
  world.entitiesWith(require: const [Enemy]).each(world.despawn);
}
