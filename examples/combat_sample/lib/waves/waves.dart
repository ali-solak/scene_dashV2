import 'dart:math' as math;

import 'package:scene_dash_v2/scene_dash_v2.dart';

import '../enemies/enemies.dart';
import '../game/actors.dart' show Player;
import '../game/game_state.dart';
import '../game/score.dart';
import '../game/sets.dart';

part 'data/config.dart';
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
