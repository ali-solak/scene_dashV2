/// The app shell: widget lifecycle around the game. Boot itself lives in
/// `game/boot.dart`; the cover/failure screen in `hud/loading_screen.dart`.
///
/// The shell walks four phases:
///
///  1. boot     — [bootCombatGame] runs behind the loading cover
///  2. cover    — the game renders its first frames still covered, so
///                pipeline compiles and warmups never jank on screen
///  3. reveal   — after two scene ticks the cover lifts
///  4. reserve  — one frame later the pooled barbarian reserve realizes,
///                off the critical path of the first visible frame
library;

import 'dart:async';

import 'package:flutter/foundation.dart'
    show TargetPlatform, ValueNotifier, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_scene/scene.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';

import 'game/boot.dart';
import 'game/camera.dart';
import 'game/camera_rig.dart';
import 'game/character_assets.dart';
import 'game/controls.dart';
import 'hud/game_hud.dart';
import 'hud/loading_screen.dart';
import 'world/data/config.dart' as config;

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

/// On-screen sticks/buttons: forced on for touch platforms, and available
/// anywhere via `--dart-define=touchControls=true`.
final bool _showTouchControls =
    const bool.fromEnvironment('touchControls') ||
    defaultTargetPlatform == TargetPlatform.android ||
    defaultTargetPlatform == TargetPlatform.iOS;

class CombatApp extends StatefulWidget {
  const CombatApp({super.key});

  @override
  State<CombatApp> createState() => _CombatAppState();
}

class _CombatAppState extends State<CombatApp> {
  // Owned for the app's whole life; the game arrives asynchronously.
  late final Scene _scene;
  late final ResourceGroup _loading;
  late final Future<void> _bootFuture;
  final ValueNotifier<String> _bootStage = ValueNotifier('renderer');

  // Boot lands in exactly one of these.
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
      final game = await bootCombatGame(_scene, _loading, _bootStage);
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
    // The boot future captures both; they must outlive a mid-boot dispose.
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
    if (_error != null) return LoadingScreen(error: _error);
    final game = _game;
    if (game == null) return LoadingScreen(stage: _bootStage);
    return Stack(
      fit: StackFit.expand,
      children: [_gameView(game), if (_coverScene) _bootCover()],
    );
  }

  /// The running game: scene view under controls under HUD, scoped by
  /// [GameHost].
  Widget _gameView(SceneGame game) {
    final cameraRig = game.world.resource<CameraRig>();
    return GameHost(
      game: game,
      child: GameControls(
        showTouchControls: _showTouchControls,
        scene: SceneView(
          _scene,
          cameraBuilder: (elapsed) => buildCombatCamera(elapsed, cameraRig),
          onTick: _onSceneTick,
        ),
        hud: const GameHud(),
      ),
    );
  }

  /// The loading screen held over the already-rendering scene (phase 2).
  Widget _bootCover() =>
      ColoredBox(color: Colors.black, child: LoadingScreen(stage: _bootStage));

  void _onSceneTick(Duration elapsed, double deltaSeconds) {
    _game?.onTick(elapsed, deltaSeconds);
    // Two covered ticks: the first real frame plus one for the warmup
    // draws to reach the GPU.
    if (++_sceneTicks == 2) _revealScene();
  }

  /// Phase 3 → 4: lift the cover, then realize the barbarian reserve one
  /// frame later so the uncovered scene reaches the screen first.
  void _revealScene() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_coverScene) return;
      setState(() => _coverScene = false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final world = _game?.world;
        if (world != null && world.hasResource<CharacterAssets>()) {
          world.resource<CharacterAssets>().loadReserve();
        }
      });
    });
  }
}
