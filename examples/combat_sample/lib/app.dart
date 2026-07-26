/// Where the app starts, and what owns the game's loading lifecycle.
///
/// Follows the README's asset-backed shape: create the [Scene] and
/// [ResourceGroup] first, track every load in the group, and mount the
/// [SceneView] immediately. The view owns progress, reveal and pipeline
/// warm-up — the app never counts frames or draws its own progress bar.
/// Once boot lands, [GameScreen] wraps that same view in `GameHost` so the
/// HUD and controls can reach the world.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_scene/scene.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';

import 'assets/character_assets.dart';
import 'boot.dart';
import 'common/camera.dart';
import 'common/camera_rig.dart';
import 'features/world/data/config.dart' as config;
import 'screens/game_screen.dart';
import 'screens/loading_screen.dart';

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

class _CombatAppState extends State<CombatApp> {
  late final Scene _scene;
  late final ResourceGroup _loading;
  late final Future<SceneGame> _booting;
  final ValueNotifier<String> _bootStage = ValueNotifier('renderer');

  /// Owned here rather than by the boot feature: the view mounts before the
  /// game exists, and its `cameraBuilder` needs a rig from the first build.
  final CameraRig _cameraRig = CameraRig()..yaw = math.pi;
  final GlobalKey _viewKey = GlobalKey();

  /// Set the moment boot lands, for the view's `onTick`. The view does not
  /// tick while it is gated, so this is never read as null in practice.
  SceneGame? _game;

  @override
  void initState() {
    super.initState();
    _scene = Scene();
    _loading = ResourceGroup();
    // Tracked so the view's reveal waits for the whole boot, not just the
    // individual asset loads. A failure is recorded, never rethrown.
    _booting = _loading.add(_boot());
  }

  Future<SceneGame> _boot() async {
    final game = await bootCombatGame(_scene, _loading, _bootStage, _cameraRig);
    _game = game;
    final world = game.world;
    if (mounted && world.hasResource<CharacterAssets>()) {
      world.resource<CharacterAssets>().loadReserve();
    }
    return game;
  }

  @override
  void dispose() {
    // Whenever boot settles, before or after this dispose. the game is
    // shut down and the loaders released. A boot that threw has no game to
    // shut down, hence `onError`.
    unawaited(
      _booting
          .then<void>((game) => game.shutdown(), onError: (_) {})
          .whenComplete(() {
            _loading.dispose();
            _bootStage.dispose();
          }),
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final view = SceneView(
      _scene,
      key: _viewKey,
      loading: _loading,
      //warmup crashes mobile
      warmUp: !config.isMobile,
      loadingBuilder: (context, progress) =>
          LoadingScreen(stage: _bootStage, progress: progress),
      cameraBuilder: (elapsed) => buildCombatCamera(elapsed, _cameraRig),
      onTick: (elapsed, deltaSeconds) => _game?.onTick(elapsed, deltaSeconds),
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.black,
        body: FutureBuilder<SceneGame>(
          future: _booting,
          builder: (context, snapshot) {
            if (snapshot.hasError) return LoadingScreen(error: snapshot.error);
            final game = snapshot.data;
            if (game == null) return view;
            return GameScreen(game: game, scene: view);
          },
        ),
      ),
    );
  }
}
