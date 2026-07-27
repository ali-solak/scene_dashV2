part of '../world.dart';

/// The moving stage: the wind clock driving grass and ocean materials,
/// and the waves breaking against the cliff.
void installWeather(GameBuilder game) {
  game
    ..world.insert(GrassWind())
    ..world.insert(WaveClock())
    ..addSystem(
      Schedules.update,
      updateWindMaterials,
      reads: const {Grass, Ocean, NodeRef},
      runIf: hasResource<Scene>(),
    )
    // Deferred spawn only (the crash entity), so no live write is declared.
    ..addSystem(
      Schedules.update,
      crashWaves,
      reads: const {},
      runIf: hasResource<Scene>(),
    );
}

/// Updates wind and water time.
void updateWindMaterials(World world) {
  final wind = world.resource<GrassWind>()..time += world.dt;

  void drive(NodeRef ref) {
    final material = ref.node.mesh?.primitives.first.material;
    if (material is PreprocessedMaterial) {
      material.parameters.setFloat('time', wind.time);
    }
  }

  world.query<NodeRef>(require: const [Grass]).each((entity, ref) {
    drive(ref);
  });
  world.query<NodeRef>(require: const [Ocean]).each((entity, ref) {
    drive(ref);
  });
}

/// Breaks a wave against the cliff every [waveCrashInterval]-ish seconds
/// at a random point along the treeline gap. Pure theatre, so it gates on
/// the scene, not the fight (the surf runs on the title screen too).
/// Game-time, so it pauses behind the menu with everything else.
void crashWaves(World world) {
  final clock = world.resource<WaveClock>();
  clock.until -= world.dt;
  if (clock.until > 0) return;
  clock.until = waveCrashInterval + clock.rng.nextDouble() * waveCrashJitter;
  final theta =
      cliffAzimuth + (clock.rng.nextDouble() - 0.5) * 2 * cliffHalfAngle * 0.85;
  final radius = groundIslandRadius + (clock.rng.nextDouble() - 0.5) * 2.5;
  // Vary each wave break.
  final intensity = 0.45 + clock.rng.nextDouble() * 1.25;
  spawnWaveCrash(
    world,
    Vector3(
      math.sin(theta) * radius,
      oceanLevel + waveCrashRise,
      math.cos(theta) * radius,
    ),
    intensity: intensity,
    seed: clock.rng.nextInt(1 << 30),
  );
}
