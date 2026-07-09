import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene_rapier/flutter_scene_rapier.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';
import 'package:vector_math/vector_math.dart' show Vector3;

import 'collectables/collectables.dart';
import 'decor/decor.dart';
import 'game/camera.dart';
import 'game/camera_rig.dart';
import 'game/game_state.dart';
import 'game/sets.dart';
import 'world/data/config.dart';
import 'hud/debug_panel.dart';
import 'hud/game_hud.dart';
import 'player/player.dart';
import 'projectiles/projectiles.dart';
import 'rocks/rocks.dart';
import 'rules/rules.dart';
import 'world/world.dart';

const bool showDebugGizmos = false;

Future<void> main() async {
  // Only what the widget shell itself writes: gameplay-owned resources
  // (GameState, Blaster, ShieldState) are constructed inside their
  // features, and the HUD reads them back through the world.
  final input = ButtonInput<GameAction>();
  final cameraRig = CameraRig();
  final fps = FpsCounter();
  final debug = DebugCubit(const DebugSettings(gizmos: showDebugGizmos));

  final game = await SceneGame.boot(
    physics: RapierWorld(gravity: Vector3(0, -gravityStrength, 0)),
    strictAccess: true,
    accessConflictPolicy: AccessConflictPolicy.error,
    features: [
      (game) {
        game
          ..addState<GameStatus>(GameStatus.playing)
          // Cross-feature phase order, declared once; features join phases
          // with `inSet:` and never reference each other's systems.
          ..configureSets(Schedules.fixedUpdate, [
            GameSets.movement,
            GameSets.actions,
          ])
          ..configureSets(Schedules.update, [GameSets.logic, GameSets.rules])
          ..world.insert(input)
          ..world.insert(cameraRig)
          ..world.insert(fps)
          // Cubit-as-resource: the same instance the tree gets through
          // BlocProvider; this system applies its choices to the world.
          ..world.insert(debug)
          ..addSystem(Schedules.frameStart, applyDebugSettings,
              reads: const {});
      },
      installWorldGeometry,
      installPlayer,
      installProjectiles,
      installRocks,
      installCollectables,
      installRules,
      installGizmos(enabled: showDebugGizmos),
      installDecor,
    ],
  );

  runApp(
    GameScope(
      game: game,
      child: BlocProvider.value(
        value: debug,
        child: RockDodgeApp(
          game: game,
          input: input,
          cameraRig: cameraRig,
          fps: fps,
        ),
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
  final FocusNode _focus = FocusNode();
  final Set<LogicalKeyboardKey> _pressed = <LogicalKeyboardKey>{};

  bool _touchLeft = false;
  bool _touchRight = false;

  // Fire is held when either source is held; the two are tracked
  // independently so releasing one never cancels the other.
  bool _spaceFire = false;
  bool _touchFire = false;

  @override
  void dispose() {
    _focus.dispose();
    // Shutting the game down runs the shutdown schedule and detaches the
    // scene driver — important for hot restart, navigation and embedding.
    widget.input.releaseAll();
    unawaited(widget.game.shutdown());
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      _pressed.add(event.logicalKey);
      if (event.logicalKey == LogicalKeyboardKey.keyR) {
        widget.game.emit(const RestartRequested());
      } else if (event.logicalKey == LogicalKeyboardKey.space && !_spaceFire) {
        _spaceFire = true;
        _syncFire();
      }
    } else if (event is KeyUpEvent) {
      _pressed.remove(event.logicalKey);
      if (event.logicalKey == LogicalKeyboardKey.space) {
        _spaceFire = false;
        _syncFire();
      }
    }
    _syncHorizontal();
    return KeyEventResult.handled;
  }

  void _onFocusChange(bool hasFocus) {
    if (hasFocus) return;
    // Losing focus cancels charging so fire can never stay stuck held.
    _spaceFire = false;
    _touchFire = false;
    _syncFire(canceled: true);
  }

  void _setTouchLeft(bool value) {
    _touchLeft = value;
    _syncHorizontal();
  }

  void _setTouchRight(bool value) {
    _touchRight = value;
    _syncHorizontal();
  }

  void _setTouchFire(bool value) {
    _touchFire = value;
    _syncFire();
  }

  void _cancelTouchFire() {
    _touchFire = false;
    _syncFire(canceled: true);
  }

  void _requestRestart() {
    _touchLeft = false;
    _touchRight = false;
    _spaceFire = false;
    _touchFire = false;
    widget.input.releaseAll();
    widget.game.emit(const RestartRequested());
  }

  /// Resolves the fire button across its two sources (space + touch), then
  /// forwards the resulting *edge* as an event. The union means releasing
  /// one source while the other is held is not a release — `ButtonInput`
  /// reports [ButtonEdge.none] and nothing is dispatched.
  void _syncFire({bool canceled = false}) {
    final held = _spaceFire || _touchFire;
    final edge = widget.input.setPressed(GameAction.fire, held);

    switch (edge) {
      case ButtonEdge.pressed:
        widget.game.emit(const FirePressed());
      case ButtonEdge.released:
        widget.game.emit(canceled ? FireCanceled() : FireReleased());

      case ButtonEdge.none:
        break;
    }
  }

  void _syncHorizontal() {
    final keyLeft =
        _pressed.contains(LogicalKeyboardKey.arrowLeft) ||
        _pressed.contains(LogicalKeyboardKey.keyA);
    final keyRight =
        _pressed.contains(LogicalKeyboardKey.arrowRight) ||
        _pressed.contains(LogicalKeyboardKey.keyD);
    // Systems read the axis via input.axis(left, right); the widget only
    // reports which directions are held.
    widget.input
      ..setPressed(GameAction.left, keyLeft || _touchLeft)
      ..setPressed(GameAction.right, keyRight || _touchRight);
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
        body: Focus(
          focusNode: _focus,
          autofocus: true,
          onKeyEvent: _onKey,
          onFocusChange: _onFocusChange,
          child: Stack(
            fit: StackFit.expand,
            children: [
              SceneView(
                widget.game.scene,
                cameraBuilder: (elapsed) =>
                    buildGameCamera(elapsed, widget.cameraRig),
                onTick: _onTick,
              ),
              GameHud(
                onLeftChanged: _setTouchLeft,
                onRightChanged: _setTouchRight,
                onFireChanged: _setTouchFire,
                onFireCanceled: _cancelTouchFire,
                onRestart: _requestRestart,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
