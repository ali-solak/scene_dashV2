part of '../world.dart';

/// The moving stage: the wind clock driving grass and ocean materials,
/// and the waves breaking against the cliff.
void installWeather(GameBuilder game) {
  game
    ..world.insert(GrassWind())
    ..world.insert(GrassBurns())
    ..world.insert(WaveClock())
    ..addSystem(
      Schedules.update,
      updateWindMaterials,
      reads: const {Ocean, NodeRef},
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

const List<String> _burnSlots = ['burn_a', 'burn_b', 'burn_c', 'burn_d'];

/// Updates wind and water time.
void updateWindMaterials(World world) {
  final wind = world.resource<GrassWind>()..time += world.dt;
  final burns = world.resource<GrassBurns>()
    ..regrow(world.dt, grassRegrowSeconds);

  void drive(NodeRef ref) {
    final material = ref.node.mesh?.primitives.first.material;
    if (material is PreprocessedMaterial) {
      material.parameters.setFloat('time', wind.time);
    }
  }

  // The blades are instanced, so the node carries no mesh to read the
  // material back from.
  final grass = world.hasResource<WorldAssets>()
      ? world.resource<WorldAssets>().grassMaterial
      : null;
  if (grass != null) {
    grass.parameters
      ..setFloat('time', wind.time)
      ..setFloat('burn_any', burns.active ? 1 : 0);
    if (burns.active) {
      for (var i = 0; i < GrassBurns.slots; i++) {
        grass.parameters.setVec4(_burnSlots[i], burns.marks[i]);
      }
    }
  }
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
