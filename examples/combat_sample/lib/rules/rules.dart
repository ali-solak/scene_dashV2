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

/// Installs resolution plus the run's win/lose loop: strike edges become
/// [HitLanded] events, [applyDamage] serves health/stagger/death, the
/// player's death drops the world into `lost`, and a restart request
/// returns it to `fighting`.
void installRules(GameBuilder game) {
  game
    // The impact bursts spawn with these, so their stores must exist.
    ..registerComponent<DespawnAfter>()
    ..registerComponent<DespawnOnExit>()
    ..addSystem(Schedules.frameStart, requestStart, reads: const {})
    ..addSystem(Schedules.frameStart, requestRestart, reads: const {})
    ..addSystem(Schedules.frameStart, toggleSkillMenu, reads: const {})
    // Each feature resets its own state in `OnEnter(fighting)`, all gated
    // on [freshRun]; rules owns only the clock.
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
    // Wind dramaturgy: reads the barbarians' phases, writes the WindState
    // resource the grass material reads (no component write to declare).
    ..addSystem(Schedules.update, driveWind, reads: const {Enemy, Brawler});
}
