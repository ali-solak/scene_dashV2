/// Routes keyboard, pointer, and touch input into game resources.
library;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/gestures.dart'
    show
        PointerDeviceKind,
        kMiddleMouseButton,
        kPrimaryButton,
        kSecondaryButton;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';

import '../hud/touch_controls.dart';
import '../features/player/player.dart' show CombatAction;
import '../features/skills/skills.dart' show Skill, SkillCast;
import '../common/game_state.dart' show GameStatus, SkillMenuToggled;
import '../common/inputs.dart';

const double _tapSlopPixels = 16;
const Duration _tapWindow = Duration(milliseconds: 280);

const List<LogicalKeyboardKey> _skillKeys = [
  LogicalKeyboardKey.digit1,
  LogicalKeyboardKey.digit2,
  LogicalKeyboardKey.digit3,
  LogicalKeyboardKey.digit4,
];

final bool showTouchControls =
    const bool.fromEnvironment('touchControls') ||
    defaultTargetPlatform == TargetPlatform.android ||
    defaultTargetPlatform == TargetPlatform.iOS;

class GameControls extends StatefulWidget {
  const GameControls({
    super.key,
    required this.scene,
    required this.hud,
    this.showTouchControls = false,
  });

  final Widget scene;
  final Widget hud;

  final bool showTouchControls;

  @override
  State<GameControls> createState() => _GameControlsState();
}

class _GameControlsState extends State<GameControls>
    with WidgetsBindingObserver {
  final FocusNode _focus = FocusNode(debugLabel: 'combat-controls');
  final Set<LogicalKeyboardKey> _pressed = <LogicalKeyboardKey>{};

  late WorldGame _game;
  late ButtonInput<CombatAction> _buttons;
  late AxisInput<MoveAxis> _axes;
  late InputBuffer<CombatAction> _buffer;
  late LookInput _look;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Global handling survives HUD focus changes.
    HardwareKeyboard.instance.addHandler(_handleKey);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _game = GameScope.of(context);
    final world = _game.world;
    _buttons = world.buttons<CombatAction>();
    _axes = world.axes<MoveAxis>();
    _buffer = world.buffer<CombatAction>();
    _look = world.resource<LookInput>();
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKey);
    WidgetsBinding.instance.removeObserver(this);
    _focus.dispose();
    _buttons.releaseAll();
    _axes.clear();
    super.dispose();
  }

  // Focus
  void _reclaimFocus() => _focus.requestFocus();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _reclaimFocus();
    } else {
      _releaseAllInput();
    }
  }

  void _releaseAllInput() {
    _pressed.clear();
    _keyAttack = false;
    _pointerAttack = false;
    _buttons.releaseAll();
    _axes.clear();
  }

  // Attack

  bool get _fighting => _game.world.state<GameStatus>() == GameStatus.fighting;

  // Keyboard and pointer attacks release independently.
  bool _keyAttack = false;
  bool _pointerAttack = false;

  void _syncAttack() {
    final edge = _buttons.setPressed(
      CombatAction.attack,
      _keyAttack || _pointerAttack,
    );
    if (edge == ButtonEdge.pressed && _fighting) {
      _buffer.record(CombatAction.attack);
    }
  }

  // Keyboard

  bool _isGameKey(LogicalKeyboardKey key) =>
      _skillKeys.contains(key) ||
      key == LogicalKeyboardKey.keyW ||
      key == LogicalKeyboardKey.keyA ||
      key == LogicalKeyboardKey.keyS ||
      key == LogicalKeyboardKey.keyD ||
      key == LogicalKeyboardKey.space ||
      key == LogicalKeyboardKey.keyJ ||
      key == LogicalKeyboardKey.tab ||
      key == LogicalKeyboardKey.keyQ ||
      key == LogicalKeyboardKey.escape;

  bool _handleKey(KeyEvent event) {
    final key = event.logicalKey;
    if (event is KeyDownEvent) {
      _pressed.add(key);
      final slot = _skillKeys.indexOf(key);
      if (slot >= 0 && slot < Skill.values.length && _fighting) {
        _game.emit(SkillCast(Skill.values[slot]));
      }
      switch (key) {
        case LogicalKeyboardKey.space when _fighting:
          _buffer.record(CombatAction.roll);
        case LogicalKeyboardKey.keyJ:
          _keyAttack = true;
          _syncAttack();
        case LogicalKeyboardKey.tab when _fighting:
          _game.emit(const LockPressed());
        case LogicalKeyboardKey.keyQ when _fighting:
          _game.emit(const LockCycled());
        case LogicalKeyboardKey.escape:
          _game.emit(const SkillMenuToggled());
      }
    } else if (event is KeyUpEvent) {
      _pressed.remove(key);
      if (key == LogicalKeyboardKey.keyJ) {
        _keyAttack = false;
        _syncAttack();
      }
    }
    _syncMoveAxes();
    return _isGameKey(key);
  }

  void _syncMoveAxes() {
    double axis(LogicalKeyboardKey negative, LogicalKeyboardKey positive) {
      var value = 0.0;
      if (_pressed.contains(negative)) value -= 1;
      if (_pressed.contains(positive)) value += 1;
      return value;
    }

    _axes
      ..setValue(
        MoveAxis.x,
        axis(LogicalKeyboardKey.keyA, LogicalKeyboardKey.keyD),
      )
      ..setValue(
        MoveAxis.y,
        axis(LogicalKeyboardKey.keyS, LogicalKeyboardKey.keyW),
      );
  }

  // Pointer

  Offset? _touchDownPosition;
  Duration? _touchDownTime;
  double _touchTravel = 0;

  void _onPointerDown(PointerDownEvent event) {
    if (event.kind == PointerDeviceKind.mouse) {
      if (event.buttons & kMiddleMouseButton != 0) {
        if (_fighting) _game.emit(const LockPressed());
      } else if (event.buttons & kPrimaryButton != 0) {
        _pointerAttack = true;
        _syncAttack();
      }
    } else {
      _touchDownPosition = event.position;
      _touchDownTime = event.timeStamp;
      _touchTravel = 0;
    }
  }

  void _onPointerUpOrCancel(PointerEvent event) {
    if (_pointerAttack) {
      _pointerAttack = false;
      _syncAttack();
    }
    if (event is PointerUpEvent &&
        event.kind != PointerDeviceKind.mouse &&
        _fighting &&
        _touchDownPosition != null &&
        _touchTravel < _tapSlopPixels &&
        (event.timeStamp - _touchDownTime!) < _tapWindow) {
      _game.emit(const LockPressed());
    }
    _touchDownPosition = null;
    _touchDownTime = null;
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (event.kind == PointerDeviceKind.mouse) {
      if ((event.buttons & kSecondaryButton) != 0) {
        _look.addDelta(event.delta.dx, event.delta.dy);
      }
    } else {
      _touchTravel += event.delta.distance;
      _look.addDelta(event.delta.dx, event.delta.dy);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focus,
      autofocus: true,
      child: Listener(
        onPointerDown: (_) => _reclaimFocus(),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Listener(
              onPointerDown: _onPointerDown,
              onPointerUp: _onPointerUpOrCancel,
              onPointerCancel: _onPointerUpOrCancel,
              onPointerMove: _onPointerMove,
              behavior: HitTestBehavior.opaque,
              child: widget.scene,
            ),
            if (widget.showTouchControls)
              GameStateBuilder<GameStatus>(
                builder: (context, status) => status == GameStatus.fighting
                    ? TouchControls(
                        onMove: (x, y) => _axes
                          ..setValue(MoveAxis.x, x)
                          ..setValue(MoveAxis.y, y),
                        onAttackChanged: (held) {
                          _pointerAttack = held;
                          _syncAttack();
                        },
                        onRoll: () => _buffer.record(CombatAction.roll),
                      )
                    : const SizedBox.shrink(),
              ),
            widget.hud,
          ],
        ),
      ),
    );
  }
}
