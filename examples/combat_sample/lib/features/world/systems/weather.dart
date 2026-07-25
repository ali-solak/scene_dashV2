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
      reads: const {Grass, Ocean, SceneNode},
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

/// Advances the wind clock and writes it into the grass and ocean
/// materials, resolved through their nodes so the seam shows in the
/// queries. Game-time on purpose: slow-mo slows wind and waves with
/// everything else, and a hitstop's 0.05 s pause is imperceptible.
void updateWindMaterials(World world) {
  final wind = world.resource<GrassWind>()..time += world.dt;

  void drive(SceneNode ref) {
    final material = ref.node.mesh?.primitives.first.material;
    if (material is PreprocessedMaterial) {
      material.parameters.setFloat('time', wind.time);
    }
  }

  world.query<SceneNode>(require: const [Grass]).each((entity, ref) {
    drive(ref);
  });
  world.query<SceneNode>(require: const [Ocean]).each((entity, ref) {
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
  // Every break rolls its own size and spread, so the surf never sparks
  // the same twice; a wide range so a small lap and a big wall are
  // obviously different.
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
