library;

import 'package:scene_dash_v2/scene_dash_v2.dart';

import '../../common/game_state.dart';
import 'data/config.dart';

part 'data/resources.dart';
part 'systems/systems.dart';

void installRules(GameBuilder game) {
  game
    ..addState<GameStatus>(GameStatus.playing)
    ..configureEvent<CreepReachedEnd>()
    ..configureEvent<CreepKilled>()
    ..world.insert(Lives())
    ..world.insert(Gold())
    ..addSystem(Schedules.update, loseLife, runIf: hasEvents<CreepReachedEnd>())
    ..addSystem(
      Schedules.update,
      collectBounty,
      runIf: hasEvents<CreepKilled>(),
    )
    ..addSystem(OnEnter(GameStatus.playing), startRun);
}
