import 'dart:math' as math;

import 'package:scene_dash_v2/scene_dash_v2.dart';
import 'package:vector_math/vector_math.dart' show Vector3;

import '../enemies/enemies.dart';
import '../fx/impact_burst.dart';
import '../game/camera_rig.dart';
import '../game/combat_math.dart';
import '../game/game_state.dart';
import '../game/score.dart';
import '../game/sets.dart';
import '../player/player.dart';
import '../skills/skills.dart';
import '../world/data/config.dart'
    show windCalmStrength, windEaseRate, windGustStrength;
import '../world/data/resources.dart' show WindState;

part 'data/config.dart';
part 'systems/systems.dart';

/// Installs combat resolution and run-state transitions.
void installRules(GameBuilder game) {
  game
    ..registerComponent<DespawnAfter>()
    ..registerComponent<DespawnOnExit>()
    ..addSystem(Schedules.frameStart, requestStart, reads: const {})
    ..addSystem(Schedules.frameStart, requestRestart, reads: const {})
    ..addSystem(Schedules.frameStart, toggleSkillMenu, reads: const {})
    ..addSystem(
      OnEnter(GameStatus.fighting),
      startRun,
      reads: const {},
      runIf: freshRun,
    )
    ..addSystem(OnEnter(GameStatus.lost), slowMotionOnLoss, reads: const {})
    ..addSystem(
      Schedules.fixedUpdate,
      resolveStrikes,
      inSet: GameSets.resolution,
      reads: const {
        Player,
        Enemy,
        Fighter,
        Brawler,
        Health,
        PlayerMotion,
        SceneTransform,
      },
      runIf: inState(GameStatus.fighting),
    )
    ..addSystem(
      Schedules.fixedUpdate,
      applyDamage,
      inSet: GameSets.resolution,
      reads: const {Enemy},
      writes: const {Fighter, Brawler, Health, Knockback, Barrier},
      after: const [resolveStrikes],
      runIf: inState(GameStatus.fighting),
    )
    ..addSystem(
      Schedules.fixedUpdate,
      clearBufferOnStagger,
      inSet: GameSets.resolution,
      reads: const {Fighter},
      after: const [applyDamage],
    )
    // Update schedule, after the fixed step's damage settles. (A setState
    // from a fixed step would apply at the next frame boundary just the
    // same — pinned by the core states suite.)
    ..addSystem(
      Schedules.update,
      checkPlayerDeath,
      reads: const {Player, Health},
      runIf: inState(GameStatus.fighting),
    )
    ..addSystem(Schedules.update, driveWind, reads: const {Enemy, Brawler});
}
