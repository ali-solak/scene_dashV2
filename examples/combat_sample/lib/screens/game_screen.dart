/// The game screen: boots a game, holds a cover over its first frames,
/// then shows it. Until the game is ready it shows [LoadingScreen],
/// the only other screen this app has.
///
/// Four phases, in order:
///
///  1. boot    — [bootCombatGame] runs while the cover shows its stages
///  2. cover   — the game renders its first frames still covered, so
///               pipeline compiles and warmups never jank on screen
///  3. reveal  — after two scene ticks the cover lifts
///  4. reserve — one frame later the pooled barbarian reserve realizes,
///               off the critical path of the first visible frame
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';

import '../boot.dart';
import 'camera.dart';
import '../common/camera_rig.dart';
import '../assets/character_assets.dart';
import 'controls.dart';
import '../hud/game_hud.dart';
import 'loading_screen.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  // Owned for this widget's whole life; the game arrives asynchronously.
  late final Scene _scene;
  late final ResourceGroup _loading;
  late final Future<void> _bootFuture;
  final ValueNotifier<String> _bootStage = ValueNotifier('renderer');

  // Boot lands in exactly one of these.
  SceneGame? _game;
  Object? _error;

  // Phase 2 → 3: covered frames counted off, then the cover lifts.
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

  /// Phase 1. Lands in `_game` or `_error`, never both.
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

  /// Phase 3, then 4: lift the cover, then realize the barbarian reserve
  /// one frame later so the uncovered scene reaches the screen first.
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

  void _onSceneTick(Duration elapsed, double deltaSeconds) {
    _game?.onTick(elapsed, deltaSeconds);
    // Two covered ticks: the first real frame plus one for the warmup
    // draws to reach the GPU.
    if (++_sceneTicks == 2) _revealScene();
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
    if (_error != null) return LoadingScreen(error: _error);
    final game = _game;
    if (game == null) return LoadingScreen(stage: _bootStage);
    return Stack(
      fit: StackFit.expand,
      children: [
        _GameView(game: game, scene: _scene, onTick: _onSceneTick),
        // Phase 2: the game is live underneath, still hidden.
        if (_coverScene) _BootCover(stage: _bootStage),
      ],
    );
  }
}

/// The running game: scene view under controls under HUD, scoped by
/// [GameHost] so the widgets below can reach the world.
class _GameView extends StatelessWidget {
  const _GameView({
    required this.game,
    required this.scene,
    required this.onTick,
  });

  final SceneGame game;
  final Scene scene;
  final void Function(Duration elapsed, double deltaSeconds) onTick;

  @override
  Widget build(BuildContext context) {
    final cameraRig = game.world.resource<CameraRig>();
    return GameHost(
      game: game,
      child: GameControls(
        showTouchControls: showTouchControls,
        scene: SceneView(
          scene,
          cameraBuilder: (elapsed) => buildCombatCamera(elapsed, cameraRig),
          onTick: onTick,
        ),
        hud: const GameHud(),
      ),
    );
  }
}

/// The loading screen held over the already-rendering scene.
class _BootCover extends StatelessWidget {
  const _BootCover({required this.stage});

  final ValueNotifier<String> stage;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Colors.black,
    child: LoadingScreen(stage: stage),
  );
}
