part of '../waves.dart';

void resetWaves(World world) => world.insert(Wave());

void runWaves(World world) {
  final wave = world.resource<Wave>();
  wave.phase.tick(world.dt);
  switch (wave.phase.state) {
    case WavePhase.breather when wave.nextWaveIn <= 0:
      wave.number++;
      wave.left = waveSize(wave.number);
      wave.phase.go(WavePhase.attacking);
    case WavePhase.attacking when wave.left == 0 && !_creepsAlive(world):
      world.emit(WaveCleared(wave.number, waveBonus(wave.number)));
      wave.phase.go(WavePhase.breather);
    case _:
  }
}

bool waveAttacking(World world) =>
    world.resource<Wave>().phase.state == WavePhase.attacking;

void spawnWaveCreep(World world) {
  final wave = world.resource<Wave>();
  if (wave.left == 0) return;
  final index = waveSize(wave.number) - wave.left--;
  final scale = waveHealthScale(wave.number);
  world.spawn(
    isRaider(wave.number, index)
        ? raiderBundle(world, scale: scale, index: index)
        : runnerBundle(world, scale: scale, index: index),
  );
}

bool _creepsAlive(World world) =>
    world.query<SceneTransform>().having<Creep>().isNotEmpty;
