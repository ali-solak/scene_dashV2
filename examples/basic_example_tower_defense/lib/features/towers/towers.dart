library;

import 'package:flutter_scene/scene.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';
import 'package:vector_math/vector_math.dart' show Vector3;

import '../../common/game_state.dart';
import '../arena/arena.dart';
import '../creeps/creeps.dart';
import '../rules/rules.dart';
import 'data/config.dart';

part 'data/components.dart';
part 'data/bundles.dart';
part 'systems/systems.dart';

void installTowers(GameBuilder game) {
  game
    ..registerComponent<Tower>()
    ..registerComponent<TowerBeam>()
    ..configureEvent<PlaceTowerRequested>()
    ..addSystem(
      Schedules.fixedUpdate,
      placeTowers,
      runIf: hasEvents<PlaceTowerRequested>(),
    )
    ..addSystem(
      Schedules.fixedUpdate,
      fireTowers,
      runIf: inState(GameStatus.playing),
    )
    ..addSystem(Schedules.update, animateBeams, runIf: hasResource<Scene>());
}
