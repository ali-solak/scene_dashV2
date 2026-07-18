import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene_rapier/flutter_scene_rapier.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';
import 'package:vector_math/vector_math.dart' show Ray, Vector3;

import '../collectables/collectables.dart';
import '../collectables/data/config.dart';
import '../game/camera_rig.dart';
import '../game/game_state.dart';
import '../game/physics_layers.dart';
import '../game/sets.dart';
import '../player/data/config.dart';
import '../player/player.dart';
import 'data/config.dart';

part 'systems/systems.dart';

/// Installs the rules and restart systems. The feature owns and inserts
/// the [GameState] run data; the HUD reads it back through the world.
void installRules(GameBuilder game) {
  game.world.insert(GameState());
  game
    ..addSystem(Schedules.frameStart, requestRestart, reads: const {})
    // Runs once at startup and again on every restart transition.
    ..addSystem(OnEnter(GameStatus.playing), startRun, reads: const {})
    ..addSystem(OnEnter(GameStatus.lost), slowMotionOnLoss, reads: const {})
    // The rules phase runs after the logic phase (see GameSets), so the
    // lose/deflect check sees this frame's collection and shield tick
    // without referencing the collectables feature's systems.
    ..addSystem(
      Schedules.update,
      evaluateGameRules,
      reads: {SceneNode, Shielded},
      writes: {PlayerKnockback},
      inSet: GameSets.rules,
      runIf: inState(GameStatus.playing),
    )
    // Camera follow observes the latest player state.
    ..addSystem(
      Schedules.update,
      playerView,
      reads: {SceneNode},
      after: [evaluateGameRules],
    );
}
