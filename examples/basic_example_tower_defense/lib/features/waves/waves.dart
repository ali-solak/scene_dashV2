library;

import 'package:scene_dash_v2/scene_dash_v2.dart';

import '../../common/game_state.dart';
import '../creeps/creeps.dart';
import 'data/config.dart';

part 'data/resources.dart';
part 'systems/systems.dart';

void installWaves(GameBuilder game) {
  game
    ..world.insert(Wave())
    ..addSystem(OnEnter(GameStatus.playing), resetWaves)
    ..addSystem(
      Schedules.fixedUpdate,
      runWaves,
      runIf: inState(GameStatus.playing),
    )
    ..addSystem(
      Schedules.fixedUpdate,
      spawnWaveCreep,
      after: [runWaves],
      runIf: inState(GameStatus.playing)
          .and(every(spawnGapSeconds))
          .and(waveAttacking),
    );
}
