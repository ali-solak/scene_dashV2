import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene_rapier/flutter_scene_rapier.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';
import 'package:vector_math/vector_math.dart' show Vector3;

import 'common/camera.dart';
import 'common/camera_rig.dart';
import 'common/game_state.dart';
import 'common/sets.dart';
import 'features/collectables/collectables.dart';
import 'features/decor/decor.dart';
import 'features/player/player.dart';
import 'features/projectiles/projectiles.dart';
import 'features/rocks/rocks.dart';
import 'features/rules/rules.dart';
import 'features/world/data/config.dart';
import 'features/world/world.dart';
import 'hud/debug_panel.dart';
import 'screens/controls.dart';
import 'package:flutter_scene/physics.dart';

const bool showDebugDraw = false;

Future<void> main() async {
  final input = ButtonInput<GameAction>();
  final cameraRig = CameraRig();
  final fps = FpsCounter();

  final game = await SceneGame.boot(
    physics: PhysicsWorld(
      RapierWorld(gravity: Vector3(0, -gravityStrength, 0)),
    ),
    strictAccess: true,
    accessConflictPolicy: AccessConflictPolicy.error,
    features: [
      (game) {
        game
          ..addState<GameStatus>(GameStatus.playing)
          ..configureSets(Schedules.fixedUpdate, [
            GameSets.movement,
            GameSets.actions,
          ])
          ..configureSets(Schedules.update, [GameSets.logic, GameSets.rules])
          ..world.insert(input)
          ..world.insert(cameraRig)
          ..world.insert(fps)
          ..world.insert(DebugSettings(debugDraw: showDebugDraw));
      },
      installWorldGeometry,
      installPlayer,
      installProjectiles,
      installRocks,
      installCollectables,
      installRules,
      installDebugDraw(enabled: showDebugDraw),
      installDecor,
    ],
  );

  runApp(
    GameScope(
      game: game,
      child: RockDodgeApp(
        game: game,
        input: input,
        cameraRig: cameraRig,
        fps: fps,
      ),
    ),
  );
}

class RockDodgeApp extends StatefulWidget {
  const RockDodgeApp({
    super.key,
    required this.game,
    required this.input,
    required this.cameraRig,
    required this.fps,
  });

  final SceneGame game;
  final ButtonInput<GameAction> input;
  final CameraRig cameraRig;
  final FpsCounter fps;

  @override
  State<RockDodgeApp> createState() => _RockDodgeAppState();
}

class _RockDodgeAppState extends State<RockDodgeApp> {
  @override
  void dispose() {
    unawaited(widget.game.shutdown());
    super.dispose();
  }

  void _onTick(Duration elapsed, double deltaSeconds) {
    widget.game.onTick(elapsed, deltaSeconds);
    widget.fps.recordFrame(deltaSeconds);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: GameControls(
          game: widget.game,
          input: widget.input,
          scene: SceneView(
            widget.game.scene,
            cameraBuilder: (elapsed) =>
                buildGameCamera(elapsed, widget.cameraRig),
            onTick: _onTick,
          ),
        ),
      ),
    );
  }
}
