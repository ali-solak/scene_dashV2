library;

import 'dart:math' show cos, sin;

import 'package:flutter_scene/kit.dart' show Steering;
import 'package:flutter_scene/scene.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';
import 'package:vector_math/vector_math.dart' show Vector3, Vector4;

import '../../common/game_state.dart';
import '../arena/data/config.dart' show route;
import '../damage/damage.dart';
import '../towers/towers.dart' show Tower;
import 'data/config.dart';

part 'data/components.dart';
part 'data/bundles.dart';
part 'systems/systems.dart';

void installCreeps(GameBuilder game) {
  game
    ..registerTag<Creep>()
    ..registerComponent<Raider>()
    ..addSystem(
      Schedules.fixedUpdate,
      steerCreeps,
      runIf: inState(GameStatus.playing),
    )
    ..addSystem(
      Schedules.fixedUpdate,
      biteTowers,
      after: [steerCreeps],
      runIf: inState(GameStatus.playing),
    )
    ..addSystem(Schedules.update, shrinkWithHealth);
}
