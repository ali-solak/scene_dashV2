import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene_rapier/flutter_scene_rapier.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';
import 'package:vector_math/vector_math.dart' show Matrix4, Vector3, Vector4;

import '../fx/instanced_pool.dart';
import '../game/game_state.dart';
import '../game/physics_layers.dart';
import 'data/config.dart';

part 'data/components.dart';
part 'data/resources.dart';
part 'data/bundles.dart';
part 'vfx/vfx.dart';
part 'systems/systems.dart';

/// Installs the rocks feature and its spawner resource — v1's plugin body
/// without the class.
void installRocks(GameBuilder game) {
  game.world
    ..insert(RockSpawner())
    ..insert(RockTrails());
  game
    ..registerTag<Rock>()
    ..registerTag<Flaming>()
    ..addSystem(
      Schedules.startup,
      spawnRockTrails,
      reads: const {},
      runIf: hasResource<Scene>(),
    )
    ..addSystem(
      OnEnter(GameStatus.playing),
      resetRocksOnRunStart,
      reads: const {},
    )
    // The spawn itself is deferred to the command boundary, so the
    // declared writes are the feature-owned types.
    ..addSystem(
      Schedules.fixedUpdate,
      spawnRocks,
      writes: {Rock, Flaming},
      runIf: inState(GameStatus.playing),
    )
    ..addSystem(Schedules.update, cleanupRocks, reads: {SceneNode})
    ..addSystem(
      Schedules.update,
      updateRockHitReactions,
      writes: {RockHitReaction, RockVisuals},
    )
    ..addSystem(Schedules.update, updateRockTrails, reads: {SceneNode});
}
