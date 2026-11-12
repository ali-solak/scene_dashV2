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
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';

import '../hud/touch_controls.dart';
import '../features/player/player.dart' show CombatAction;
import '../features/skills/skills.dart' show Skill, SkillCast;
import '../common/game_state.dart' show GameStatus, SkillMenuToggled;
import '../common/inputs.dart';

const double _tapSlopPixels = 16;
const Duration _tapWindow = Duration(milliseconds: 280);

final Map<LogicalKeyboardKey, CombatAction> combatKeys = {
  LogicalKeyboardKey.keyJ: CombatAction.attack,
  LogicalKeyboardKey.space: CombatAction.roll,
  LogicalKeyboardKey.keyK: CombatAction.heavy,
  LogicalKeyboardKey.keyF: CombatAction.heavy,
};

const List<LogicalKeyboardKey> _skillKeys = [
  LogicalKeyboardKey.digit1,
  LogicalKeyboardKey.digit2,
  LogicalKeyboardKey.digit3,
  LogicalKeyboardKey.digit4,
];

final Set<LogicalKeyboardKey> _moveKeys = {
  LogicalKeyboardKey.keyW,
  LogicalKeyboardKey.keyA,
  LogicalKeyboardKey.keyS,
  LogicalKeyboardKey.keyD,
};

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
  final Set<LogicalKeyboardKey> _moving = <LogicalKeyboardKey>{};

  late WorldGame _game;
  late ButtonInput<CombatAction> _buttons;
  late AxisInput<MoveAxis> _axes;
  late LookInput _look;
  CombatAction? _mouseAction;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _game = GameScope.of(context);
    final world = _game.world;
    _buttons = world.buttons<CombatAction>();
    _axes = world.axes<MoveAxis>();
    _look = world.resource<LookInput>();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _releaseOwnInput();
    _focus.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _focus.requestFocus();
    } else {
      _releaseOwnInput();
    }
  }

  void _releaseOwnInput() {
    _moving.clear();
    _axes.clear();
    _releaseMouse(cancel: true);
  }

  bool get _fighting => _game.world.state<GameStatus>() == GameStatus.fighting;

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final key = event.logicalKey;
    if (_moveKeys.contains(key)) {
      if (event is KeyUpEvent) {
        _moving.remove(key);
      } else {
        _moving.add(key);
      }
      _syncMoveAxes();
      return KeyEventResult.handled;
    }
    if (event is! KeyDownEvent) {
      return _isEventKey(key) ? KeyEventResult.handled : KeyEventResult.ignored;
    }
    final slot = _skillKeys.indexOf(key);
    if (slot >= 0 && slot < Skill.values.length && _fighting) {
      _game.emit(SkillCast(Skill.values[slot]));
    }
    switch (key) {
      case LogicalKeyboardKey.tab when _fighting:
        _game.emit(const LockPressed());
      case LogicalKeyboardKey.keyQ when _fighting:
        _game.emit(const LockCycled());
      case LogicalKeyboardKey.escape:
        _game.emit(const SkillMenuToggled());
    }
    return _isEventKey(key) ? KeyEventResult.handled : KeyEventResult.ignored;
  }

  bool _isEventKey(LogicalKeyboardKey key) =>
      _skillKeys.contains(key) ||
      key == LogicalKeyboardKey.tab ||
      key == LogicalKeyboardKey.keyQ ||
      key == LogicalKeyboardKey.escape;

  void _onFocusChange(bool focused) {
    if (focused) return;
    _moving.clear();
    _syncMoveAxes();
  }

  void _syncMoveAxes() {
    double axis(LogicalKeyboardKey negative, LogicalKeyboardKey positive) {
      var value = 0.0;
      if (_moving.contains(negative)) value -= 1;
      if (_moving.contains(positive)) value += 1;
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

  void _releaseMouse({bool cancel = false}) {
    final action = _mouseAction;
    if (action == null) return;
    _mouseAction = null;
    if (cancel) {
      _buttons.cancel(action);
    } else {
      _buttons.release(action);
    }
  }

  Offset? _touchDownPosition;
  Duration? _touchDownTime;
  double _touchTravel = 0;

  void _onPointerDown(PointerDownEvent event) {
    if (event.kind == PointerDeviceKind.mouse) {
      if (event.buttons & kMiddleMouseButton != 0) {
        if (_fighting) _game.emit(const LockPressed());
      } else if (event.buttons & kPrimaryButton != 0) {
        _releaseMouse();
        _mouseAction = HardwareKeyboard.instance.isShiftPressed
            ? CombatAction.heavy
            : CombatAction.attack;
        _buttons.press(_mouseAction!);
      }
    } else {
      _touchDownPosition = event.position;
      _touchDownTime = event.timeStamp;
      _touchTravel = 0;
    }
  }

  void _onPointerUp(PointerEvent event) {
    _releaseMouse(cancel: event is PointerCancelEvent);
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
      canRequestFocus: false,
      onKeyEvent: _onKey,
      onFocusChange: _onFocusChange,
      child: InputBindings<CombatAction>(
        keys: combatKeys,
        focusNode: _focus,
        child: Listener(
          onPointerDown: (_) => _focus.requestFocus(),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Listener(
                onPointerDown: _onPointerDown,
                onPointerUp: _onPointerUp,
                onPointerCancel: _onPointerUp,
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
                        )
                      : const SizedBox.shrink(),
                ),
              widget.hud,
            ],
          ),
        ),
      ),
    );
  }
}
