/// Widgets that read world state.
library;

import 'package:flutter/widgets.dart';
import 'package:scene_dash_v2_core/advanced.dart' show EventReader;
import 'package:scene_dash_v2_core/scene_dash_v2_core.dart';

import 'game_scope.dart';
import 'scene_game.dart';

/// Listens to game frames.
abstract class _FrameTickState<W extends StatefulWidget> extends State<W> {
  WorldGame? _game;

  WorldGame get game => _game!;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = GameScope.of(context);
    if (identical(next, _game)) return;
    final previous = _game;
    previous?.frameTick.removeListener(_onFrameTick);
    _game = next;
    next.frameTick.addListener(_onFrameTick);
    attached(previous);
  }

  @override
  void dispose() {
    _game?.frameTick.removeListener(_onFrameTick);
    detached();
    super.dispose();
  }

  void _onFrameTick() {
    if (!mounted) return;
    frameTick();
  }

  /// Called when the game changes.
  void attached(WorldGame? previous) {}

  /// The widget is going away; release game-side resources.
  void detached() {}

  /// One rendered frame ended; the world is fully resolved.
  void frameTick();
}

/// Rebuilds when a selected component value changes.
class EntityBuilder<T extends Object, S> extends StatefulWidget {
  const EntityBuilder({
    super.key,
    required Entity this.entity,
    required this.select,
    required this.builder,
    this.absent,
  }) : require = null,
       exclude = null;

  /// Watches the first entity matching the filters.
  const EntityBuilder.matching({
    super.key,
    this.require = const <Type>[],
    this.exclude = const <Type>[],
    required this.select,
    required this.builder,
    this.absent,
  }) : entity = null;

  /// The entity to watch (handle form; null in `.matching` form).
  final Entity? entity;

  /// `.matching` filters (tags or components beside [T]); null in the
  /// handle form.
  final List<Type>? require;
  final List<Type>? exclude;

  /// Selects the watched value from the component; compared with `==`.
  final S Function(T component) select;

  /// Builds from the selected value; runs only when it changed.
  final Widget Function(BuildContext context, S value) builder;

  /// Shown while the entity is dead or lacks [T].
  final Widget? absent;

  @override
  State<EntityBuilder<T, S>> createState() => _EntityBuilderState<T, S>();
}

class _EntityBuilderState<T extends Object, S>
    extends _FrameTickState<EntityBuilder<T, S>> {
  bool _present = false;
  S? _value;

  @override
  void attached(WorldGame? previous) {
    // Ensure the component store exists.
    SpawnQueue.of(game.world).ensureStore<T>();
    _read(rebuild: false);
  }

  @override
  void frameTick() => _read(rebuild: true);

  void _read({required bool rebuild}) {
    final require = widget.require;
    final component = require == null
        ? game.world.tryGet<T>(widget.entity!)
        : game.world
              .query<T>(require: require, exclude: widget.exclude!)
              .firstOrNull
              ?.$2;
    if (component == null) {
      if (_present && rebuild) setState(() => _present = false);
      _present = false;
      return;
    }
    final value = widget.select(component);
    if (_present && value == _value) return;
    _present = true;
    _value = value;
    if (rebuild) setState(() {});
  }

  @override
  Widget build(BuildContext context) => _present
      ? widget.builder(context, _value as S)
      : (widget.absent ?? const SizedBox.shrink());
}

/// Rebuilds when a selected world value changes.
class WorldBuilder<S> extends StatefulWidget {
  const WorldBuilder({
    super.key,
    required this.select,
    required this.builder,
    this.equals,
  }) : trigger = null,
       duration = 0,
       pulseBuilder = null,
       child = null;

  /// The pulse form: the frame `trigger(previous, next)` passes,
  /// [pulseBuilder] receives 1.0, decaying to 0 over [duration] seconds of
  /// wall time.
  const WorldBuilder.pulse({
    super.key,
    required this.select,
    required bool Function(S previous, S next) this.trigger,
    required this.duration,
    required Widget Function(BuildContext context, double pulse, Widget? child)
    this.pulseBuilder,
    this.child,
    this.equals,
  }) : builder = null,
       assert(duration > 0, 'pulse duration is seconds and must be positive');

  /// Selects the watched value from the world; compared with `==`.
  final S Function(World world) select;

  /// Custom equality check.
  final bool Function(S previous, S next)? equals;

  /// Builds from the selected value; runs only when it changed. (Plain
  /// form; null in the pulse form.)
  final Widget Function(BuildContext context, S value)? builder;

  /// Fires the pulse when a changed selection crosses this edge (pulse
  /// form; null in the plain form). Evaluated only when `next != previous`.
  final bool Function(S previous, S next)? trigger;

  /// Seconds the pulse takes to decay 1 → 0, on wall time (pulse form).
  final double duration;

  /// Builds from the live pulse; runs every frame while it is above 0 and
  /// not at all at rest. Curving is the call site's job (`pulse * pulse`).
  final Widget Function(BuildContext context, double pulse, Widget? child)?
  pulseBuilder;

  /// Static subtree handed to [pulseBuilder] unrebuilt (the
  /// `AnimatedBuilder` convention).
  final Widget? child;

  @override
  State<WorldBuilder<S>> createState() => _WorldBuilderState<S>();
}

class _WorldBuilderState<S> extends _FrameTickState<WorldBuilder<S>> {
  late S _value;
  double _pulse = 0;

  @override
  void attached(WorldGame? previous) => _value = widget.select(game.world);

  @override
  void frameTick() {
    final value = widget.select(game.world);
    final equals = widget.equals;
    final same = equals != null ? equals(_value, value) : value == _value;
    final trigger = widget.trigger;
    if (trigger == null) {
      if (same) return;
      setState(() => _value = value);
      return;
    }
    final fired = !same && trigger(_value, value);
    _value = value;
    var pulse = _pulse;
    if (fired) {
      pulse = 1;
    } else if (pulse > 0) {
      pulse -= game.world.resource<FrameTime>().unscaledDelta / widget.duration;
      if (pulse < 0) pulse = 0;
    }
    if (pulse == _pulse) return;
    setState(() => _pulse = pulse);
  }

  @override
  Widget build(BuildContext context) {
    final pulseBuilder = widget.pulseBuilder;
    if (pulseBuilder != null) {
      return pulseBuilder(context, _pulse, widget.child);
    }
    return widget.builder!(context, _value);
  }
}

/// Rebuilds when game state changes.
class GameStateBuilder<S extends Object> extends StatefulWidget {
  const GameStateBuilder({super.key, required this.builder});

  /// Builds for the active state value; runs on transitions only.
  final Widget Function(BuildContext context, S state) builder;

  @override
  State<GameStateBuilder<S>> createState() => _GameStateBuilderState<S>();
}

class _GameStateBuilderState<S extends Object>
    extends _FrameTickState<GameStateBuilder<S>> {
  late S _state;

  @override
  void attached(WorldGame? previous) => _state = game.world.state<S>();

  @override
  void frameTick() {
    final state = game.world.state<S>();
    if (state == _state) return;
    setState(() => _state = state);
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _state);
}

/// Listens for world events.
class WorldEventListener<E extends Object> extends StatefulWidget {
  const WorldEventListener({
    super.key,
    required this.onEvent,
    required this.child,
  });

  /// Called once per event, after the frame that emitted it resolved.
  final void Function(BuildContext context, E event) onEvent;

  /// The subtree this listener wraps (rendered untouched).
  final Widget child;

  @override
  State<WorldEventListener<E>> createState() => _WorldEventListenerState<E>();
}

class _WorldEventListenerState<E extends Object>
    extends _FrameTickState<WorldEventListener<E>> {
  EventReader<E>? _reader;

  @override
  void attached(WorldGame? previous) {
    final reader = _reader;
    if (reader != null && previous != null) {
      SpawnQueue.of(previous.world).releaseReader<E>(reader);
    }
    _reader = SpawnQueue.of(game.world).acquireReader<E>();
  }

  @override
  void detached() {
    final reader = _reader;
    final game = _game;
    if (reader != null && game != null) {
      SpawnQueue.of(game.world).releaseReader<E>(reader);
    }
    _reader = null;
  }

  @override
  void frameTick() {
    _reader?.forEach((event) => widget.onEvent(context, event));
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
