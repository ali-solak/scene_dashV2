import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';
import 'package:vector_math/vector_math.dart' show Ray, Vector3;

import '../collectables/collectables.dart';
import '../collectables/data/config.dart';
import '../../common/camera_rig.dart';
import '../../common/game_state.dart';
import '../../common/physics_layers.dart';
import '../../common/sets.dart';
import '../player/data/config.dart';
import '../player/player.dart';
import 'data/config.dart';
import 'package:flutter_scene/physics.dart';

part 'systems/systems.dart';

void installRules(GameBuilder game) {
  game.world.insert(GameState());
  game
    ..addSystem(Schedules.frameStart, requestRestart, reads: const {})
    ..addSystem(OnEnter(GameStatus.playing), startRun, reads: const {})
    ..addSystem(OnEnter(GameStatus.lost), slowMotionOnLoss, reads: const {})
    ..addSystem(
      Schedules.update,
      evaluateGameRules,
      reads: {NodeRef, Shielded},
      writes: {PlayerKnockback},
      inSet: GameSets.rules,
      runIf: inState(GameStatus.playing),
    )
    ..addSystem(
      Schedules.update,
      playerView,
      reads: {NodeRef},
      after: [evaluateGameRules],
    );
}
