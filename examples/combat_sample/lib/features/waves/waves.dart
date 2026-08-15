import 'dart:math' as math;

import 'package:scene_dash_v2/scene_dash_v2.dart';

import '../enemies/enemies.dart';
import '../../common/actors.dart' show Player;
import '../../common/game_state.dart';
import '../../common/score.dart';
import '../../common/sets.dart';

part 'data/config.dart';
part 'data/plan.dart';
part 'data/resources.dart';
part 'systems/systems.dart';

/// Installs wave spawning, scoring, and between-wave recovery.
void installWaves(GameBuilder game) {
  game
    ..registerComponent<Transforming>()
    ..world.insert(WaveState())
    ..world.insert(Score())
    ..addSystem(
      Schedules.fixedUpdate,
      advanceWaves,
      inSet: GameSets.waves,
      reads: const {Enemy, Brawler, Player},
      writes: const {Health},
      runIf: inState(GameStatus.fighting),
    )
    ..addSystem(
      OnEnter(GameStatus.fighting),
      resetWaves,
      reads: const {Enemy},
      runIf: freshRun,
    );
}
