// The combat slice: boot, the feature cascade, and the widget shell. WASD
// move, mouse to look; left button tap = strike, hold = heavy; Space =
// roll; middle mouse or Tab toggles lock-on, Q cycles targets; 1-4 cast.
//
//   flutter run --enable-flutter-gpu
//
// Input handling lives in `game/controls.dart` — this file is composition.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene_rapier/flutter_scene_rapier.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';
import 'package:vector_math/vector_math.dart' show Vector3;

import 'decor/decor.dart';
import 'enemies/enemies.dart';
import 'game/camera.dart';
import 'game/camera_rig.dart';
import 'game/character_assets.dart';
import 'game/controls.dart';
import 'game/game_state.dart';
import 'game/inputs.dart';
import 'game/sets.dart';
import 'hud/game_hud.dart';
import 'player/player.dart';
import 'rules/rules.dart';
import 'skills/skills.dart';
import 'waves/waves.dart';
import 'world/data/assets.dart';
import 'world/data/config.dart';
import 'world/world.dart';

/// Touch HUD: on by default on mobile; `--dart-define=touchControls=true`
/// forces it elsewhere (testing the layout on desktop).
final bool _showTouchControls =
    const bool.fromEnvironment('touchControls') ||
    defaultTargetPlatform == TargetPlatform.android ||
    defaultTargetPlatform == TargetPlatform.iOS;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Scene.initializeStaticResources();
  await RapierWorld.ensureInitialized();
  final assets = await loadWorldAssets();
  CharacterAssets? characters;
  try {
    // Waves borrow from this pool and hand models back on despawn.
    characters = await loadCharacterAssets(barbarianCount: barbarianPoolSize);
  } on Object catch (error) {
    // The fight still runs on graybox capsules.
    debugPrint('combat_sample: character assets unavailable: $error');
  }

  // Only what the widget shell itself writes: buttons/axes/buffer/look are
  // fed by the input widgets, the camera rig by the player feature.
  final buttons = ButtonInput<CombatAction>();
  final axes = AxisInput<MoveAxis>();
  final buffer = InputBuffer<CombatAction>(window: bufferWindow);
  final look = LookInput();

  final cameraRig = CameraRig()..yaw = math.pi;

  final game = await SceneGame.boot(
    physics: RapierWorld(gravity: Vector3(0, -gravityStrength, 0)),
    strictAccess: true,
    accessConflictPolicy: AccessConflictPolicy.error,
    features: [
      (game) {
        game
          ..addState<GameStatus>(GameStatus.fighting)
          ..configureSets(Schedules.fixedUpdate, [
            GameSets.movement,
            GameSets.enemyMovement,
            GameSets.actions,
            GameSets.resolution,
            GameSets.waves,
          ])
          ..configureSets(Schedules.update, [GameSets.logic])
          ..world.insert(buttons)
          ..world.insert(axes)
          ..world.insert(buffer)
          ..world.insert(look)
          ..world.insert(cameraRig);
        if (characters != null) game.world.insert(characters);
      },
      installWorld(assets),
      installDecor,
      installPlayer,
      installEnemies,
      installWaves,
      installSkills,
      installRules,
    ],
  );

  runApp(
    GameScope(
      game: game,
      child: CombatApp(
        game: game,
        buttons: buttons,
        axes: axes,
        buffer: buffer,
        look: look,
        cameraRig: cameraRig,
      ),
    ),
  );
}

class CombatApp extends StatefulWidget {
  const CombatApp({
    super.key,
    required this.game,
    required this.buttons,
    required this.axes,
    required this.buffer,
    required this.look,
    required this.cameraRig,
  });

  final SceneGame game;
  final ButtonInput<CombatAction> buttons;
  final AxisInput<MoveAxis> axes;
  final InputBuffer<CombatAction> buffer;
  final LookInput look;
  final CameraRig cameraRig;

  @override
  State<CombatApp> createState() => _CombatAppState();
}

class _CombatAppState extends State<CombatApp> {
  @override
  void dispose() {
    // Runs the shutdown schedule and detaches the scene driver — important
    // for hot restart, navigation and embedding.
    unawaited(widget.game.shutdown());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.black,
        body: GameControls(
          game: widget.game,
          buttons: widget.buttons,
          axes: widget.axes,
          buffer: widget.buffer,
          look: widget.look,
          showTouchControls: _showTouchControls,
          scene: SceneView(
            widget.game.scene,
            cameraBuilder: (elapsed) =>
                buildCombatCamera(elapsed, widget.cameraRig),
            onTick: widget.game.onTick,
            warmUp:
                defaultTargetPlatform != TargetPlatform.android &&
                defaultTargetPlatform != TargetPlatform.iOS,
            loadingBuilder: (context, progress) =>
                const Center(child: CircularProgressIndicator()),
          ),
          hud: GameHud(
            onRestart: () => widget.game.emit(const RestartRequested()),
            onToggleMenu: () => widget.game.emit(const SkillMenuToggled()),
            onBuySkill: (skill) =>
                widget.game.emit(SkillUpgradeRequested(skill)),
            onBuyVitality: () => widget.game.emit(const VitalityRequested()),
          ),
        ),
      ),
    );
  }
}
