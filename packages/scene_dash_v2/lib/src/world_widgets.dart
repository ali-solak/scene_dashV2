/// The world as a Flutter data source: pull-based widgets over one
/// `frameTick` heartbeat with select-and-compare — a widget rebuilds only
/// when the value it selected actually changed, no cubit bridge, no
/// per-frame snapshots pushed out of the world.
///
/// All primitives resolve their game from the enclosing `GameScope`
/// (nearest-ancestor wins); none takes a game parameter. The write path is
/// unchanged and non-negotiable: UI → `ButtonInput` / `world.emit`; never
/// direct component mutation.
library;

import 'package:flutter/widgets.dart';
import 'package:scene_dash_v2_core/advanced.dart' show EventReader;
import 'package:scene_dash_v2_core/scene_dash_v2_core.dart';

import 'game_scope.dart';
import 'scene_game.dart';

/// Shared plumbing: subscribe to the enclosing game's `frameTick`, resub
/// when the scope's game changes, and unsubscribe on dispose.
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

  /// The game changed (first attach included; [previous] was the old one).
  void attached(WorldGame? previous) {}

  /// The widget is going away; release game-side resources.
  void detached() {}

  /// One rendered frame ended; the world is fully resolved.
  void frameTick();
}

/// Watches one component's selected value on one entity, rebuilding only
/// when that value changes:
///
/// ```dart
/// EntityBuilder<Health, double>(
///   entity: player,                 // handle form: from a spawn return or
///   select: (h) => h.current,       //   event data
///   builder: (context, hp) => HealthBar(hp),
/// )
///
/// EntityBuilder<Health, double>.matching(
///   require: const [Player],        // matching form: the first entity with
///   select: (h) => h.current,       //   Health + Player, re-resolved through
///   builder: (context, hp) =>       //   the world each frame — no handle
///       HealthBar(hp),              //   crosses into the widget tree
/// )
/// ```
///
/// Both type arguments usually infer from the closures. While the entity
/// is dead or lacks [T] — or, for `.matching`, nothing matches — [absent]
/// shows instead (default: nothing); selection resumes when a match comes
/// back, a *respawned* entity included. [select] must return a value with
/// meaningful `==` (numbers, strings, records) — returning the component
/// itself would compare identical and never rebuild. `.matching` is for
/// match sets meant to be unique (THE player, THE boss); resolving by one
/// component while watching another stays the `WorldBuilder<Entity?>` +
/// `EntityBuilder` composition.
class EntityBuilder<T extends Object, S> extends StatefulWidget {
  const EntityBuilder({
    super.key,
    required Entity this.entity,
    required this.select,
    required this.builder,
    this.absent,
  }) : require = null,
       exclude = null;

  /// Watches the first entity carrying [T], every type in [require] and
  /// none in [exclude] — resolved through the world each frame.
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
    // A typed site (§ lazy stores): ensure [T]'s store exists and claim any
    // parked parts, so a component spawned before any system queried its
    // type is still visible to this widget.
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

/// Watches any world-derived value — query counts, resources, aggregates —
/// rebuilding only when it changes:
///
/// ```dart
/// WorldBuilder<int>(
///   select: (world) => world.query<Rock>().count(),
///   builder: (context, rocks) => Text('$rocks rocks'),
/// )
/// ```
///
/// [select] runs once per rendered frame; keep it cheap and give it
/// meaningful `==` (see `EntityBuilder`).
class WorldBuilder<S> extends StatefulWidget {
  const WorldBuilder({super.key, required this.select, required this.builder});

  /// Selects the watched value from the world; compared with `==`.
  final S Function(World world) select;

  /// Builds from the selected value; runs only when it changed.
  final Widget Function(BuildContext context, S value) builder;

  @override
  State<WorldBuilder<S>> createState() => _WorldBuilderState<S>();
}

class _WorldBuilderState<S> extends _FrameTickState<WorldBuilder<S>> {
  late S _value;

  @override
  void attached(WorldGame? previous) => _value = widget.select(game.world);

  @override
  void frameTick() {
    final value = widget.select(game.world);
    if (value == _value) return;
    setState(() => _value = value);
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _value);
}

/// Typed overlay routing off `CurrentState<S>` — HUD while playing,
/// results on game-over — replacing string-keyed overlay maps:
///
/// ```dart
/// GameStateBuilder<GameStatus>(
///   builder: (context, s) => switch (s) {
///     GameStatus.playing  => const BattleHud(),
///     GameStatus.gameOver => const ResultsScreen(),
///   },
/// )
/// ```
///
/// Rebuilds only on transitions. The state machine must be registered
/// (`addState<S>` in a feature).
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

/// One-shot reactions to world events — flashes, navigation, SFX — with
/// widget-lifetime cleanup:
///
/// ```dart
/// WorldEventListener<HitLanded>(
///   onEvent: (context, hit) => showDamageFlash(context),
///   child: const BattleView(),
/// )
/// ```
///
/// Events are delivered once per rendered frame, in emission order, after
/// the world resolved. The subscription leases a channel reader from the
/// world's spawn queue pool and returns it on dispose, so an unmounted
/// listener never lags a channel or leaks one.
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
  State<WorldEventListener<E>> createState() =>
      _WorldEventListenerState<E>();
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
