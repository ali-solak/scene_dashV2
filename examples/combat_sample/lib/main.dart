// The combat slice: boot, the feature cascade, and the widget shell. WASD
// move, mouse to look; left button tap = strike, hold = heavy; Space =
// roll; middle mouse or Tab toggles lock-on, Q cycles targets; 1-4 cast.
//
//   flutter run --enable-flutter-gpu
//
// Input handling lives in `game/controls.dart` — this file is composition.
import 'dart:math' as math;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'hud/ink.dart';
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
  if (kIsWeb) {
    await BrowserContextMenu.disableContextMenu();
  }

  if (!kIsWeb && isMobile) {
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  runApp(const CombatApp());
}

class CombatApp extends StatelessWidget {
  const CombatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.black,
        body: GameBootstrap<SceneGame>(
          boot: _bootGame,
          loading: (context) => const _LoadingScreen(),
          error: (context, error) => _LoadingScreen(error: error),
          builder: (context, game) => _GameSurface(game: game),
        ),
      ),
    );
  }
}

Future<SceneGame> _bootGame() async {
  // `SceneGame.boot` calls `Scene.initializeStaticResources` itself; only
  // the physics engine has to be brought up before we hand it a world.
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

  return SceneGame.boot(
    physics: RapierWorld(gravity: Vector3(0, -gravityStrength, 0)),
    strictAccess: true,
    accessConflictPolicy: AccessConflictPolicy.error,
    features: [
      (game) {
        game
          // The run opens on the title screen: every gameplay system
          // gates on `fighting`, so the clearing simply stands there.
          ..addState<GameStatus>(GameStatus.title)
          ..configureSets(Schedules.fixedUpdate, [
            GameSets.movement,
            GameSets.enemyMovement,
            GameSets.actions,
            GameSets.resolution,
            GameSets.waves,
          ])
          ..configureSets(Schedules.update, [GameSets.logic])
          // Input surfaces: written by the widgets in `game/controls.dart`,
          // read by the player and camera systems. Inserted here so both
          // sides find the same instance (buffer and rig need non-default
          // construction, so they cannot be left to lazy creation).
          ..world.insert(ButtonInput<CombatAction>())
          ..world.insert(AxisInput<MoveAxis>())
          ..world.insert(InputBuffer<CombatAction>(window: bufferWindow))
          ..world.insert(LookInput())
          ..world.insert(CameraRig()..yaw = math.pi);
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
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen({this.error});

  final Object? error;

  @override
  Widget build(BuildContext context) {
    final failed = error != null;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'COMBAT SAMPLE',
            style: TextStyle(
              color: HudInk.bone,
              fontSize: 30,
              fontWeight: FontWeight.w600,
              letterSpacing: 12,
              height: 1,
            ),
          ),
          const SizedBox(height: 18),
          if (!failed)
            const SizedBox(
              width: 150,
              child: LinearProgressIndicator(
                minHeight: 2,
                backgroundColor: HudInk.ruleFaint,
                color: HudInk.steel,
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                '$error',
                textAlign: TextAlign.center,
                style: const TextStyle(color: HudInk.ash, fontSize: 12),
              ),
            ),
          const SizedBox(height: 14),
          Text(
            failed ? 'FAILED TO START' : 'LOADING',
            style: const TextStyle(
              color: HudInk.ash,
              fontSize: 11,
              letterSpacing: 4,
            ),
          ),
        ],
      ),
    );
  }
}

class _GameSurface extends StatelessWidget {
  const _GameSurface({required this.game});

  final SceneGame game;

  @override
  Widget build(BuildContext context) {
    final cameraRig = game.world.resource<CameraRig>();
    return GameControls(
      showTouchControls: _showTouchControls,
      scene: SceneView(
        game.scene,
        cameraBuilder: (elapsed) => buildCombatCamera(elapsed, cameraRig),
        onTick: game.onTick,

        loadingBuilder: (context, progress) =>
            const Center(child: CircularProgressIndicator()),
      ),
      hud: const GameHud(),
    );
  }
}
