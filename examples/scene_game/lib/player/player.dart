import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene_rapier/flutter_scene_rapier.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';
import 'package:vector_math/vector_math.dart' show Matrix4, Vector3, Vector4;

import '../fx/anim.dart';
import '../game/game_state.dart';
import '../game/physics_layers.dart';
import '../game/sets.dart';
import '../world/data/config.dart';
import '../world/data/ramp.dart';
import 'animation/gait.dart';
import 'data/config.dart';

part 'data/components.dart';
part 'data/resources.dart';
part 'data/bundles.dart';
part 'systems/systems.dart';

/// Installs the player feature — v1's plugin body without the class.
void installPlayer(GameBuilder game) {
  game.world.insert(PlayerKnockback());
  game
    ..registerTag<Player>()
    ..addSystem(
      Schedules.startup,
      spawnPlayer,
      writes: {Player, SceneNode, PlayerVisuals},
      runIf: hasResource<Scene>(),
    )
    ..addSystem(
      OnEnter(GameStatus.playing),
      resetPlayerOnRunStart,
      writes: {SceneNode, PlayerVisuals},
    )
    ..addSystem(
      Schedules.fixedUpdate,
      movePlayer,
      writes: {SceneNode},
      inSet: GameSets.movement,
      runIf: inState(GameStatus.playing),
    )
    ..addSystem(
      Schedules.update,
      animateCrabLegs,
      writes: {PlayerVisuals},
      runIf: inState(GameStatus.playing),
    );
}
