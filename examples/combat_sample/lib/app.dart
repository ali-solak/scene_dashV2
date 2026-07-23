import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart'
    show
        TargetPlatform,
        ValueNotifier,
        debugPrint,
        defaultTargetPlatform,
        kIsWeb;
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
import 'world/data/config.dart' as config;
import 'world/world.dart';

Future<void> runCombatApp() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) {
    await BrowserContextMenu.disableContextMenu();
  } else if (config.isMobile) {
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }
  runApp(const CombatApp());
}

class CombatApp extends StatefulWidget {
  const CombatApp({super.key});

  @override
  State<CombatApp> createState() => _CombatAppState();
}

final bool _showTouchControls =
    const bool.fromEnvironment('touchControls') ||
    defaultTargetPlatform == TargetPlatform.android ||
    defaultTargetPlatform == TargetPlatform.iOS;

class _CombatAppState extends State<CombatApp> {
  late final Scene _scene;
  late final ResourceGroup _loading;
  late final Future<void> _bootFuture;
  final ValueNotifier<String> _bootStage = ValueNotifier('renderer');

  SceneGame? _game;
  Object? _error;
  int _sceneTicks = 0;
  bool _coverScene = true;

  @override
  void initState() {
    super.initState();
    _scene = Scene();
    _loading = ResourceGroup();
    _bootFuture = _boot();
    _loading.add(_bootFuture);
  }

  Future<void> _boot() async {
    try {
      final game = await _bootCombatGame(_scene, _loading, _bootStage);
      if (mounted) {
        setState(() => _game = game);
      } else {
        await game.shutdown();
      }
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  @override
  void dispose() {
    unawaited(_game?.shutdown());
    unawaited(
      _bootFuture.whenComplete(() {
        _loading.dispose();
        _bootStage.dispose();
      }),
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(backgroundColor: Colors.black, body: _surface()),
    );
  }

  Widget _surface() {
    final error = _error;
    if (error != null) return _LoadingScreen(error: error);

    final game = _game;
    if (game == null) return _LoadingScreen(stage: _bootStage);

    final cameraRig = game.world.resource<CameraRig>();
    final sceneView = SceneView(
      _scene,
      cameraBuilder: (elapsed) => buildCombatCamera(elapsed, cameraRig),
      onTick: _onSceneTick,
    );

    final hosted = GameHost(
      game: game,
      child: GameControls(
        showTouchControls: _showTouchControls,
        scene: sceneView,
        hud: const GameHud(),
      ),
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        hosted,
        if (_coverScene)
          ColoredBox(
            color: Colors.black,
            child: _LoadingScreen(stage: _bootStage),
          ),
      ],
    );
  }

  void _onSceneTick(Duration elapsed, double deltaSeconds) {
    _game?.onTick(elapsed, deltaSeconds);
    _sceneTicks++;
    if (_sceneTicks != 2) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_coverScene) return;
      setState(() => _coverScene = false);
      // Let the uncovered scene reach the screen before realizing the
      // precompiled reserve bodies.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final game = _game;
        if (game != null && game.world.hasResource<CharacterAssets>()) {
          game.world.resource<CharacterAssets>().loadReserve();
        }
      });
    });
  }
}

Future<SceneGame> _bootCombatGame(
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

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen({this.error, this.stage});

  final Object? error;
  final ValueNotifier<String>? stage;

  @override
  Widget build(BuildContext context) {
    final failed = error != null;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Defend the isle',
            style: TextStyle(
              color: HudInk.bone,
              fontSize: 30,
              fontWeight: FontWeight.w600,
              letterSpacing: 12,
              height: 1,
            ),
          ),
          const SizedBox(height: 18),
          if (failed)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                '$error',
                textAlign: TextAlign.center,
                style: const TextStyle(color: HudInk.ash, fontSize: 12),
              ),
            )
          else
            SizedBox(
              width: 150,
              child: LinearProgressIndicator(
                minHeight: 2,
                backgroundColor: HudInk.ruleFaint,
                color: HudInk.steel,
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
          if (!failed && stage != null) ...[
            const SizedBox(height: 6),
            ValueListenableBuilder<String>(
              valueListenable: stage!,
              builder: (context, value, _) => Text(
                value.toUpperCase(),
                style: const TextStyle(
                  color: HudInk.steel,
                  fontSize: 9,
                  letterSpacing: 3,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
