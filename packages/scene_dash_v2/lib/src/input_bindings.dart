import 'package:flutter/foundation.dart' show debugPrint, mapEquals;
import 'package:flutter/gestures.dart' show kTouchSlop;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:scene_dash_v2_core/scene_dash_v2_core.dart';

import 'game_scope.dart';

class InputBindings<A extends Object> extends StatefulWidget {
  const InputBindings({
    super.key,
    required this.keys,
    required this.child,
    this.input,
    this.autofocus = true,
    this.focusNode,
  });

  final Map<LogicalKeyboardKey, A> keys;
  final ButtonInput<A>? input;
  final bool autofocus;
  final FocusNode? focusNode;
  final Widget child;

  @override
  State<InputBindings<A>> createState() => _InputBindingsState<A>();
}

class _InputBindingsState<A extends Object> extends State<InputBindings<A>> {
  final Map<LogicalKeyboardKey, A> _keysDown = <LogicalKeyboardKey, A>{};
  final Map<int, A> _pointers = <int, A>{};
  final Map<A, int> _holds = <A, int>{};
  late final AppLifecycleListener _lifecycle;
  FocusNode? _ownedFocus;
  ButtonInput<A>? _input;

  FocusNode get _focus =>
      widget.focusNode ??
      (_ownedFocus ??= FocusNode(debugLabel: 'InputBindings<$A>'));

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onStateChange: _onLifecycle);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bindInput();
  }

  @override
  void didUpdateWidget(InputBindings<A> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!mapEquals(oldWidget.keys, widget.keys)) _releaseKeys();
    if (!identical(oldWidget.input, widget.input)) _bindInput();
  }

  void _bindInput() {
    final next = widget.input ?? GameScope.of(context).world.buttons<A>();
    if (identical(next, _input)) return;
    _releaseAll();
    _input = next;
    assert(_checkInputIsLatched(next));
  }

  bool _checkInputIsLatched(ButtonInput<A> input) {
    final game = GameScope.maybeOf(context);
    final held = game?.world.resources.tryGet<ButtonInput<A>>();
    if (identical(held, input)) return true;
    final report = game?.engine.app.onDiagnostic ?? debugPrint;
    report(
      'InputBindings<$A> writes a ButtonInput<$A> that is not the world resource, '
      'so the frame loop never latches its edges: pressed() works, '
      'justPressed()/justReleased() stay false. Drop input: to use '
      'world.buttons<$A>(), or world.insert(yourInput) at install time.',
    );
    return true;
  }

  @override
  void dispose() {
    _releaseAll();
    _lifecycle.dispose();
    _ownedFocus?.dispose();
    super.dispose();
  }

  void _hold(A action) {
    final count = (_holds[action] ?? 0) + 1;
    _holds[action] = count;
    if (count == 1) _input?.press(action);
  }

  void _unhold(A action, {bool cancel = false}) {
    final count = (_holds[action] ?? 0) - 1;
    if (count > 0) {
      _holds[action] = count;
      return;
    }
    _holds.remove(action);
    final input = _input;
    if (input == null) return;
    if (cancel) {
      input.cancel(action);
    } else {
      input.release(action);
    }
  }

  void _releaseKeys() {
    final held = _keysDown.values.toList(growable: false);
    _keysDown.clear();
    for (final action in held) {
      _unhold(action, cancel: true);
    }
  }

  void _releaseAll() {
    _keysDown.clear();
    _pointers.clear();
    final input = _input;
    if (input != null) {
      for (final action in _holds.keys) {
        input.cancel(action);
      }
    }
    _holds.clear();
  }

  void _onLifecycle(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _releaseAll();
  }

  void _onFocusChange(bool focused) {
    if (!focused) _releaseKeys();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final key = event.logicalKey;
    if (event is KeyUpEvent) {
      final held = _keysDown.remove(key);
      if (held == null) return KeyEventResult.ignored;
      _unhold(held);
      return KeyEventResult.handled;
    }
    final action = widget.keys[key];
    if (action == null) return KeyEventResult.ignored;
    if (event is KeyDownEvent && !_keysDown.containsKey(key)) {
      _keysDown[key] = action;
      _hold(action);
    }
    return KeyEventResult.handled;
  }

  void _pointerDown(int pointer, A action) {
    final previous = _pointers[pointer];
    if (previous == action) return;
    _pointers[pointer] = action;
    _hold(action);
    if (previous != null) _unhold(previous);
  }

  void _pointerUp(int pointer, {bool cancel = false}) {
    final action = _pointers.remove(pointer);
    if (action != null) _unhold(action, cancel: cancel);
  }

  @override
  Widget build(BuildContext context) {
    return _InputBindingsScope<A>(
      state: this,
      child: Focus(
        focusNode: _focus,
        autofocus: widget.autofocus,
        onKeyEvent: _onKey,
        onFocusChange: _onFocusChange,
        child: widget.child,
      ),
    );
  }
}

class _InputBindingsScope<A extends Object> extends InheritedWidget {
  const _InputBindingsScope({required this.state, required super.child});

  final _InputBindingsState<A> state;

  @override
  bool updateShouldNotify(_InputBindingsScope<A> oldWidget) =>
      !identical(state, oldWidget.state);
}

class TouchAction<A extends Object> extends StatefulWidget {
  const TouchAction({
    super.key,
    required this.action,
    required this.child,
    this.cancelOnDrag = false,
  });

  final A action;
  final bool cancelOnDrag;
  final Widget child;

  @override
  State<TouchAction<A>> createState() => _TouchActionState<A>();
}

class _TouchActionState<A extends Object> extends State<TouchAction<A>> {
  final Map<int, Offset> _downAt = <int, Offset>{};
  _InputBindingsState<A>? _bindings;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = context
        .dependOnInheritedWidgetOfExactType<_InputBindingsScope<A>>();
    if (scope == null) {
      throw FlutterError(
        'TouchAction<$A> needs an InputBindings<$A> above it in the tree.',
      );
    }
    if (!identical(scope.state, _bindings)) _cancelAll();
    _bindings = scope.state;
  }

  @override
  void didUpdateWidget(TouchAction<A> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.action != widget.action) _cancelAll();
  }

  @override
  void dispose() {
    _cancelAll();
    super.dispose();
  }

  void _cancelAll() {
    final bindings = _bindings;
    if (bindings == null || !bindings.mounted) {
      _downAt.clear();
      return;
    }
    for (final pointer in _downAt.keys) {
      bindings._pointerUp(pointer, cancel: true);
    }
    _downAt.clear();
  }

  void _down(PointerDownEvent event) {
    _downAt[event.pointer] = event.position;
    _bindings?._pointerDown(event.pointer, widget.action);
  }

  void _move(PointerMoveEvent event) {
    if (!widget.cancelOnDrag) return;
    final origin = _downAt[event.pointer];
    if (origin == null) return;
    if ((event.position - origin).distance <= kTouchSlop) return;
    _downAt.remove(event.pointer);
    _bindings?._pointerUp(event.pointer, cancel: true);
  }

  void _end(PointerEvent event, {required bool cancel}) {
    if (_downAt.remove(event.pointer) == null) return;
    _bindings?._pointerUp(event.pointer, cancel: cancel);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _down,
      onPointerMove: _move,
      onPointerUp: (event) => _end(event, cancel: false),
      onPointerCancel: (event) => _end(event, cancel: true),
      child: widget.child,
    );
  }
}
