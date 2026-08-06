library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';

import '../common/game_state.dart';
import '../hud/game_hud.dart';

class GameControls extends StatefulWidget {
  const GameControls({
    super.key,
    required this.game,
    required this.input,
    required this.scene,
  });

  final SceneGame game;
  final ButtonInput<GameAction> input;

  final Widget scene;

  @override
  State<GameControls> createState() => _GameControlsState();
}

class _GameControlsState extends State<GameControls> {
  final FocusNode _focus = FocusNode();
  final Set<LogicalKeyboardKey> _pressed = <LogicalKeyboardKey>{};

  bool _touchLeft = false;
  bool _touchRight = false;

  bool _spaceFire = false;
  bool _touchFire = false;

  @override
  void dispose() {
    _focus.dispose();
    widget.input.releaseAll();
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
    widget.input
      ..setPressed(GameAction.left, keyLeft || _touchLeft)
      ..setPressed(GameAction.right, keyRight || _touchRight);
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      onFocusChange: _onFocusChange,
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.scene,
          GameHud(
            onLeftChanged: _setTouchLeft,
            onRightChanged: _setTouchRight,
            onFireChanged: _setTouchFire,
            onFireCanceled: _cancelTouchFire,
            onRestart: _requestRestart,
          ),
        ],
      ),
    );
  }
}
