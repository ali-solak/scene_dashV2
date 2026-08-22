library;

import 'package:flutter_scene/scene.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';

import '../../common/game_state.dart';
import '../arena/data/config.dart';
import 'data/config.dart';

part 'data/components.dart';
part 'data/bundles.dart';
part 'systems/systems.dart';

void installCreeps(GameBuilder game) {
  game
    ..registerTag<Creep>()
    ..addSystem(
      Schedules.fixedUpdate,
      spawnCreep,
      runIf: inState(GameStatus.playing).and(every(creepSpawnSeconds)),
    )
    ..addSystem(
      Schedules.fixedUpdate,
      walkPath,
      runIf: inState(GameStatus.playing),
    )
    ..addSystem(Schedules.fixedUpdate, reapCreeps, after: [walkPath]);
}
