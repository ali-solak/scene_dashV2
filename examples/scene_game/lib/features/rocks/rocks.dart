import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';
import 'package:vector_math/vector_math.dart' show Matrix4, Vector3, Vector4;

import '../../fx/particles.dart' as fx;
import '../../fx/particle_texture.dart';
import '../../common/bounds.dart';
import '../../common/game_state.dart';
import '../../common/physics_layers.dart';
import 'data/config.dart';
import 'package:flutter_scene/physics.dart';

part 'data/components.dart';
part 'data/resources.dart';
part 'data/bundles.dart';
part 'vfx/vfx.dart';
part 'systems/systems.dart';

void installRocks(GameBuilder game) {
  game
    ..registerTag<Rock>()
    ..registerTag<Flaming>()
    ..registerComponent<RockSpawner>()
    ..registerComponent<FlameTrailEmitter>()
    ..observe<Flaming>(onAdd: igniteRock, onRemove: extinguishRock)
    ..observe<RockHitReaction>(onRemove: clearHitShell)
    ..addSystem(
      OnEnter(GameStatus.playing),
      spawnRockSpawner,
      writes: {RockSpawner},
    )
    ..addSystem(
      Schedules.fixedUpdate,
      spawnRocks,
      writes: {Rock, Flaming, RockSpawner},
      runIf: hasResource<Scene>().and(inState(GameStatus.playing)),
    )
    ..addSystem(
      Schedules.startup,
      spawnFlameTrailEmitter,
      writes: {FlameTrailEmitter},
      runIf: hasResource<Scene>(),
    )
    ..addSystem(
      Schedules.update,
      updateFlameTrails,
      reads: {NodeRef},
      writes: {FlameTrailEmitter},
    )
    ..addSystem(
      Schedules.update,
      updateRockHitReactions,
      reads: {RockHitReaction},
      writes: {RockVisuals},
    );
}
