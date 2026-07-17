import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene_rapier/flutter_scene_rapier.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';
import 'package:vector_math/vector_math.dart' show Matrix4, Vector3, Vector4;

import '../fx/particles.dart' as fx;
import '../fx/particle_texture.dart';
import '../game/game_state.dart';
import '../game/physics_layers.dart';
import 'data/config.dart';

part 'data/components.dart';
part 'data/resources.dart';
part 'data/bundles.dart';
part 'vfx/vfx.dart';
part 'systems/systems.dart';

/// Installs the rocks feature — v1's plugin body without the class. The
/// spawner is a run-scoped process entity (spawned on every
/// `OnEnter(playing)`). Flame trails are upstream particle emitters
/// attached per rock by the `Flaming` observer pair — the scene advances
/// them; no trail system, no trail resource.
void installRocks(GameBuilder game) {
  game
    ..registerTag<Rock>()
    ..registerTag<Flaming>()
    ..registerComponent<RockSpawner>()
    // The tag is the single source of the flaming look; runtime ignition
    // is one `world.add(rock, const Flaming())`. The observers own the
    // full payload: material swap plus trail-emitter attach/detach.
    ..observe<Flaming>(onAdd: igniteRock, onRemove: extinguishRock)
    // Invariant: no reaction ⇒ shell hidden, on every removal path.
    ..observe<RockHitReaction>(onRemove: clearHitShell)
    ..addSystem(
      OnEnter(GameStatus.playing),
      spawnRockSpawner,
      writes: {RockSpawner},
    )
    // The spawn itself is deferred to the command boundary, so the
    // declared writes are the feature-owned types.
    ..addSystem(
      Schedules.fixedUpdate,
      spawnRocks,
      writes: {Rock, Flaming, RockSpawner},
      runIf: inState(GameStatus.playing),
    )
    ..addSystem(Schedules.update, cleanupRocks, reads: {SceneNode})
    ..addSystem(
      Schedules.update,
      updateRockHitReactions,
      writes: {RockHitReaction, RockVisuals},
    );
}
