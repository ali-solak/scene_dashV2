import 'package:flutter/animation.dart' show Curves;
import 'package:flutter_scene/scene.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';
import 'package:vector_math/vector_math.dart' show Matrix4, Vector3, Vector4;

import '../../common/game_state.dart';
import '../../common/physics_layers.dart';
import '../../common/sets.dart';
import '../world/data/config.dart';
import '../world/data/ramp.dart';
import 'animation/gait.dart';
import 'data/config.dart';
import 'package:flutter_scene/physics.dart';

part 'data/components.dart';
part 'data/resources.dart';
part 'data/bundles.dart';
part 'systems/systems.dart';

void installPlayer(GameBuilder game) {
  game
    ..registerTag<Player>()
    ..registerComponent<PlayerKnockback>()
    ..addSystem(
      Schedules.startup,
      spawnPlayer,
      writes: {Player, NodeRef, PlayerVisuals},
      runIf: hasResource<Scene>(),
    )
    ..addSystem(
      OnEnter(GameStatus.playing),
      attachPlayerKnockback,
      reads: {Player},
      writes: {PlayerKnockback},
    )
    ..addSystem(
      OnEnter(GameStatus.playing),
      resetPlayerOnRunStart,
      writes: {NodeRef, PlayerVisuals},
    )
    ..addSystem(
      Schedules.fixedUpdate,
      movePlayer,
      writes: {NodeRef, PlayerKnockback},
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
