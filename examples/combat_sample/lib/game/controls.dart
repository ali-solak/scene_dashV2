/// [GameControls] wraps the whole game surface — scene AND hud — and
/// writes into the input resources `main` inserted. It owns no gameplay:
/// held state goes to `ButtonInput`/`AxisInput`, edges to `InputBuffer`,
/// pointer deltas to `LookInput`, and one-shot intents are emitted as
/// events. Systems read those; nothing reads this.
library;

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
import '../player/player.dart' show CombatAction;
import '../skills/skills.dart' show Skill, SkillCast;
import 'game_state.dart' show GameStatus, SkillMenuToggled;
import 'inputs.dart';

/// A touch that barely moved and released quickly is a lock press, not a
/// camera swipe.
const double _tapSlopPixels = 16;
const Duration _tapWindow = Duration(milliseconds: 280);

/// Cast keys, in skill-bar order: digit N casts `Skill.values[N - 1]`, so
/// a new skill is bound by existing in the enum rather than by being
/// named here. The HUD numbers its slots off the same index.
const List<LogicalKeyboardKey> _skillKeys = [
  LogicalKeyboardKey.digit1,
  LogicalKeyboardKey.digit2,
  LogicalKeyboardKey.digit3,
  LogicalKeyboardKey.digit4,
];

class GameControls extends StatefulWidget {
  const GameControls({
    super.key,
    required this.scene,
    required this.hud,
    this.showTouchControls = false,
  });

  /// The scene view. Only this gets the look/attack pointer handling —
  /// dragging across the HUD must not swing the camera.
  final Widget scene;

  /// Drawn over the scene. Inside the focus-reclaiming listener, so its
  /// buttons cannot leave the keyboard dead behind them.
  final Widget hud;

  final bool showTouchControls;

  @override
  State<GameControls> createState() => _GameControlsState();
}

class _GameControlsState extends State<GameControls>
    with WidgetsBindingObserver {
  final FocusNode _focus = FocusNode(debugLabel: 'combat-controls');
  final Set<LogicalKeyboardKey> _pressed = <LogicalKeyboardKey>{};

  // The input surfaces `main` inserted, reached through the enclosing
  // GameScope rather than threaded down as constructor arguments. This
  // widget writes them and the player/camera systems read them — the
  // README's UI-to-world path, one direction only. They live for the
  // game's lifetime, so a one-time resolve is enough.
  late WorldGame _game;
  late ButtonInput<CombatAction> _buttons;
  late AxisInput<MoveAxis> _axes;
  late InputBuffer<CombatAction> _buffer;
  late LookInput _look;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Game keys ride the HARDWARE keyboard, not the focus tree. A widget
    // `onKeyEvent` only fires while this node holds focus, and focus gets
    // stolen out from under a game constantly (capture overlays, a HUD
    // click) — the reclaim below only heals POINTER input, so a keyboard
    // cast was swallowed and only landed on the second press. A global
    // handler is dispatched every key regardless of who holds focus.
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

  // --- Focus ---------------------------------------------------------------
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

  // --- Attack --------------------------------------------------------------

  // Attack is held when either source (J, left button) is held; tracked
  // independently so releasing one never releases the other.
  bool _keyAttack = false;
  bool _pointerAttack = false;

  void _syncAttack() {
    // Buffered on the edge; held state decides light vs heavy.
    if (_buttons.setPressed(
          CombatAction.attack,
          _keyAttack || _pointerAttack,
        ) ==
        ButtonEdge.pressed) {
      _buffer.record(CombatAction.attack);
    }
  }

  // --- Keyboard ------------------------------------------------------------

  /// A key this game acts on — consumed (returns true) so it never doubles
  /// as focus traversal (Tab) or leaks to a system shortcut.
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

  /// The global hardware-keyboard handler (see [initState]). Only a
  /// KeyDownEvent casts — a held key repeats as KeyRepeatEvent, which must
  /// not spam a skill.
  bool _handleKey(KeyEvent event) {
    final key = event.logicalKey;
    if (event is KeyDownEvent) {
      _pressed.add(key);
      final slot = _skillKeys.indexOf(key);
      if (slot >= 0 && slot < Skill.values.length) {
        _game.emit(SkillCast(Skill.values[slot]));
      }
      switch (key) {
        case LogicalKeyboardKey.space:
          _buffer.record(CombatAction.roll);
        case LogicalKeyboardKey.keyJ:
          _keyAttack = true;
          _syncAttack();
        case LogicalKeyboardKey.tab:
          _game.emit(const LockPressed());
        case LogicalKeyboardKey.keyQ:
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

  // --- Pointer (scene only) ------------------------------------------------

  Offset? _touchDownPosition;
  Duration? _touchDownTime;
  double _touchTravel = 0;

  void _onPointerDown(PointerDownEvent event) {
    if (event.kind == PointerDeviceKind.mouse) {
      if (event.buttons & kMiddleMouseButton != 0) {
        _game.emit(const LockPressed());
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
        _touchDownPosition != null &&
        _touchTravel < _tapSlopPixels &&
        (event.timeStamp - _touchDownTime!) < _tapWindow) {
      _game.emit(const LockPressed());
    }
    _touchDownPosition = null;
    _touchDownTime = null;
  }

  // Drag-to-look: without pointer capture, free hover-look spins the
  // camera on every cursor move and dies at the window edge — so the
  // orbit is right-button drag on desktop and any swipe on touch (touch
  // never attacks from the scene: the HUD button owns that). The camera
  // system ignores the deltas while a lock frames the fight.
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
    // Keys are handled globally (see [initState]/[_handleKey]), not through
    // this node — so a stolen focus can no longer swallow a cast. The Focus
    // stays only to hold [autofocus] and keep stray Tab traversal off the
    // HUD widgets; the pointer reclaim below is now belt-and-suspenders.
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
            // Only while there is a fight to steer: the stick and the
            // attack button over a title screen or a death panel are
            // controls for something that is not happening.
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
