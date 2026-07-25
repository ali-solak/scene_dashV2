/// Boots the combat game: renderer and physics init, asset loads (each
/// stage reported through the boot cover), then the feature set under
/// `strictAccess`. The app shell in `app.dart` owns the widget lifecycle;
/// this file owns everything between "binding ready" and "game running".
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueNotifier, debugPrint;
import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene_rapier/flutter_scene_rapier.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';
import 'package:vector_math/vector_math.dart' show Vector3;

import 'features/decor/decor.dart';
import 'features/enemies/enemies.dart';
import 'features/player/player.dart';
import 'features/rules/rules.dart';
import 'features/skills/skills.dart';
import 'features/waves/waves.dart';
import 'features/world/data/assets.dart';
import 'features/world/data/config.dart' as config;
import 'features/world/world.dart';
import 'common/camera_rig.dart';
import 'assets/character_assets.dart';
import 'common/game_state.dart';
import 'common/inputs.dart';
import 'common/sets.dart';

Future<SceneGame> bootCombatGame(
  Scene scene,
  ResourceGroup loading,
  ValueNotifier<String> stage,
) async {
  stage.value = 'renderer';
  await Scene.initializeStaticResources();
  stage.value = 'physics';
  await RapierWorld.ensureInitialized();

  stage.value = 'world materials';
  final assets = await loadWorldAssets(loading: loading);
  stage.value = 'character rigs';
  final characters = await _loadCharacters(loading);

  stage.value = 'the clearing';
  final game = await SceneGame.boot(
    scene: scene,
    physics: RapierWorld(gravity: Vector3(0, -config.gravityStrength, 0)),
    strictAccess: true,
    accessConflictPolicy: AccessConflictPolicy.error,
    features: [
      _configureCombat(characters),
      installWorld(assets),
      installDecor,
      installPlayer,
      installEnemies,
      installWaves,
      installSkills,
      installRules,
    ],
  );
  stage.value = 'first frame';
  return game;
}

Future<CharacterAssets?> _loadCharacters(ResourceGroup loading) async {
  try {
    return await loadCharacterAssets(
      barbarianCount: barbarianPoolSize,
      loading: loading,
    );
  } on Object catch (error) {
    debugPrint('combat_sample: character assets unavailable: $error');
    return null;
  }
}

Feature _configureCombat(CharacterAssets? characters) => (game) {
  game
    ..addState<GameStatus>(GameStatus.title)
    ..configureSets(Schedules.fixedUpdate, [
      GameSets.movement,
      GameSets.enemyMovement,
      GameSets.actions,
      GameSets.resolution,
      GameSets.waves,
    ])
    ..configureSets(Schedules.update, [GameSets.logic])
    ..world.insert(ButtonInput<CombatAction>())
    ..world.insert(AxisInput<MoveAxis>())
    ..world.insert(InputBuffer<CombatAction>(window: bufferWindow))
    ..world.insert(LookInput())
    ..world.insert(CameraRig()..yaw = math.pi);
  if (characters != null) game.world.insert(characters);
};
