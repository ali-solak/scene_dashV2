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

/// Installs the wave loop: barbarians arrive in waves that grow in size,
/// health and power, giants show up every few waves, and kills pay
/// points (banked in [Score], spent on skills). This feature owns
/// [WaveState] and the spawning; enemies owns how a barbarian behaves
/// once it is on the field.
void installWaves(GameBuilder game) {
  game
    ..registerComponent<Transforming>()
    ..world.insert(WaveState())
    ..world.insert(Score())
    // Fixed step, in its own set after resolution: the living count it
    // reads is this step's, post-damage.
    ..addSystem(
      Schedules.fixedUpdate,
      advanceWaves,
      inSet: GameSets.waves,
      reads: const {Enemy, Brawler, Player},
      // The between-wave heal. Safe against resolution's damage because
      // this set runs after it.
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
