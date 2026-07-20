/// Everything between a human and the world: keyboard, mouse, touch, and
/// the focus bookkeeping that decides whether any of it arrives.
///
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
import 'game_state.dart' show SkillMenuToggled;
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
    required this.game,
    required this.buttons,
    required this.axes,
    required this.buffer,
    required this.look,
    required this.scene,
    required this.hud,
    this.showTouchControls = false,
  });

  final SceneGame game;
  final ButtonInput<CombatAction> buttons;
  final AxisInput<MoveAxis> axes;
  final InputBuffer<CombatAction> buffer;
  final LookInput look;

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _focus.dispose();
    widget.buttons.releaseAll();
    widget.axes.clear();
    super.dispose();
  }

  // --- Focus ---------------------------------------------------------------

  /// Takes the keyboard back.
  ///
  /// Pointer events reach a [Listener] whatever holds focus; key events
  /// only reach `onKeyEvent` while THIS node has it. So every way of
  /// losing focus presents identically — the mouse still works, the
  /// keyboard is dead, and the window looks perfectly focused. Two known
  /// ways in, and they want the same cure:
  ///
  ///  * a capture overlay (NVIDIA ShadowPlay, Steam, Discord) takes OS
  ///    focus and hands it back without Flutter re-focusing anything;
  ///    `autofocus` fires once at mount and never again;
  ///  * any HUD button takes focus when clicked and simply keeps it,
  ///    which kills WASD every time the skill menu is opened by mouse.
  ///
  /// Unconditional on purpose: `hasFocus` can read true while a
  /// descendant actually holds the keyboard, and re-requesting focus you
  /// already have is free.
  void _reclaimFocus() => _focus.requestFocus();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _reclaimFocus();
  }

  /// Losing focus for real (alt-tab) must not leave keys stuck down: the
  /// world would keep walking with nobody holding W.
  void _onFocusChange(bool hasFocus) {
    if (hasFocus) return;
    _pressed.clear();
    _keyAttack = false;
    _pointerAttack = false;
    widget.buttons.releaseAll();
    widget.axes.clear();
  }

  // --- Attack --------------------------------------------------------------

  // Attack is held when either source (J, left button) is held; tracked
  // independently so releasing one never releases the other.
  bool _keyAttack = false;
  bool _pointerAttack = false;

  void _syncAttack() {
    // Buffered on the edge; held state decides light vs heavy.
    if (widget.buttons.setPressed(
          CombatAction.attack,
          _keyAttack || _pointerAttack,
        ) ==
        ButtonEdge.pressed) {
      widget.buffer.record(CombatAction.attack);
    }
  }

  // --- Keyboard ------------------------------------------------------------

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      _pressed.add(event.logicalKey);
      final slot = _skillKeys.indexOf(event.logicalKey);
      if (slot >= 0 && slot < Skill.values.length) {
        widget.game.emit(SkillCast(Skill.values[slot]));
      }
      switch (event.logicalKey) {
        case LogicalKeyboardKey.space:
          widget.buffer.record(CombatAction.roll);
        case LogicalKeyboardKey.keyJ:
          _keyAttack = true;
          _syncAttack();
        case LogicalKeyboardKey.tab:
          widget.game.emit(const LockPressed());
        case LogicalKeyboardKey.keyQ:
          widget.game.emit(const LockCycled());
        case LogicalKeyboardKey.escape:
          widget.game.emit(const SkillMenuToggled());
      }
    } else if (event is KeyUpEvent) {
      _pressed.remove(event.logicalKey);
      if (event.logicalKey == LogicalKeyboardKey.keyJ) {
        _keyAttack = false;
        _syncAttack();
      }
    }
    _syncMoveAxes();
    return KeyEventResult.handled;
  }

  void _syncMoveAxes() {
    double axis(LogicalKeyboardKey negative, LogicalKeyboardKey positive) {
      var value = 0.0;
      if (_pressed.contains(negative)) value -= 1;
      if (_pressed.contains(positive)) value += 1;
      return value;
    }

    widget.axes
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
        widget.game.emit(const LockPressed());
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
      widget.game.emit(const LockPressed());
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
        widget.look.addDelta(event.delta.dx, event.delta.dy);
      }
    } else {
      _touchTravel += event.delta.distance;
      widget.look.addDelta(event.delta.dx, event.delta.dy);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      onFocusChange: _onFocusChange,
      // The OUTER listener spans the hud as well as the scene, and only
      // ever reclaims focus. Pointer events dispatch to every listener on
      // the hit-test path, so this still fires when a HUD button handles
      // the same click — which is exactly the case that used to eat the
      // keyboard.
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
              TouchControls(
                onMove: (x, y) => widget.axes
                  ..setValue(MoveAxis.x, x)
                  ..setValue(MoveAxis.y, y),
                onAttackChanged: (held) {
                  _pointerAttack = held;
                  _syncAttack();
                },
                onRoll: () => widget.buffer.record(CombatAction.roll),
              ),
            widget.hud,
          ],
        ),
      ),
    );
  }
}
