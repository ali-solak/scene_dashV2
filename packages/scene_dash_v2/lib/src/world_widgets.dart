/// Widgets that read world state.
library;

import 'package:flutter/foundation.dart' show mapEquals, setEquals;
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
  void initState() {
    super.initState();
    _validateConfiguration();
  }

  @override
  void didUpdateWidget(covariant W oldWidget) {
    super.didUpdateWidget(oldWidget);
    _validateConfiguration();
  }

  void _validateConfiguration() {
    final interval = pollInterval;
    if (interval != null && interval.isNegative) {
      throw ArgumentError.value(interval, 'every', 'must not be negative');
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = GameScope.of(context);
    if (identical(next, _game)) return;
    final previous = _game;
    previous?.frameTick.removeListener(_onFrameTick);
    _game = next;
    _resetPolling();
    next.frameTick.addListener(_onFrameTick);
    attached(previous);
  }

  @override
  void dispose() {
    _game?.frameTick.removeListener(_onFrameTick);
    detached();
    super.dispose();
  }

  /// Minimum time between polls. Null polls every frame.
  Duration? get pollInterval => null;

  /// Counted on the frame clock's unscaled delta, not a [Stopwatch]: it is
  /// the same wall time the pulse decays on, and it is what tests drive.
  double _sincePoll = 0;
  bool _polled = false;

  void _resetPolling() {
    _sincePoll = 0;
    _polled = false;
  }

  void _onFrameTick() {
    if (!mounted) return;
    final interval = pollInterval;
    if (interval != null) {
      _sincePoll += game.world.resource<FrameTime>().unscaledDelta;
      // The first tick always polls, so a mounted builder is never stale.
      if (_polled && _sincePoll < interval.inMicroseconds / 1e6) return;
      _sincePoll = 0;
      _polled = true;
    }
    frameTick();
  }

  /// Called when the game changes.
  void attached(WorldGame? previous) {}

  /// The widget is going away; release game-side resources.
  void detached() {}

  /// One rendered frame ended; the world is fully resolved.
  void frameTick();
}

final class _Selection<S> {
  _Selection(this.value) : _baseline = _baselineOf(value);

  final S value;
  final Object? _baseline;

  S get snapshot => _baseline is S ? _baseline : value;

  bool matches(S next) => _sameSelection(_baseline, next);

  static Object? _baselineOf(Object? value) => switch (value) {
    Set() => value.toSet(),
    Map() => Map.of(value),
    Iterable() => value.toList(growable: false),
    _ => value,
  };

  static bool _sameSelection(Object? baseline, Object? next) =>
      switch ((baseline, next)) {
        (Set baseline, Set next) => setEquals(baseline, next),
        (Map baseline, Map next) => mapEquals(baseline, next),
        (List baseline, Iterable next) when next is! Set => _sameElements(
          baseline,
          next,
        ),
        _ => baseline == next,
      };

  static bool _sameElements(List<Object?> baseline, Iterable<Object?> next) {
    var index = 0;
    for (final element in next) {
      if (index >= baseline.length || baseline[index] != element) return false;
      index++;
    }
    return index == baseline.length;
  }
}

/// Rebuilds when a selected component value changes.
class EntityBuilder<T extends Object, S> extends StatefulWidget {
  const EntityBuilder({
    super.key,
    required Entity this.entity,
    required this.select,
    required this.builder,
    this.absent,
    this.every,
  }) : where = null;

  /// Watches an entity matching the filters until it stops matching.
  const EntityBuilder.matching({
    super.key,
    this.where,
    required this.select,
    required this.builder,
    this.absent,
    this.every,
  }) : entity = null;

  /// The entity to watch (handle form; null in `.matching` form).
  final Entity? entity;

  final QueryView1<T> Function(QueryView1<T> query)? where;

  /// Rebuilds when the selection changes: `==`, with lists, sets, maps, and
  /// iterables compared by contents, one level deep.
  final S Function(T component) select;

  /// Builds from the selected value. Frame ticks rebuild only on changes;
  /// parent rebuilds can also invoke this callback.
  final Widget Function(BuildContext context, S value) builder;

  /// Shown while the entity is dead or lacks [T].
  final Widget? absent;

  /// Minimum wall time between frame polls. Null reads every frame.
  /// Zero also reads every frame; negative intervals throw on mount or update.
  /// Widget updates and game changes refresh the selection immediately.
  final Duration? every;

  @override
  State<EntityBuilder<T, S>> createState() => _EntityBuilderState<T, S>();
}

class _EntityBuilderState<T extends Object, S>
    extends _FrameTickState<EntityBuilder<T, S>> {
  _Selection<S>? _selection;
  bool _needsRead = false;

  QueryView1<T>? _matchQuery;
  Entity? _matched;
  int _missRevision = -1;

  @override
  Duration? get pollInterval => widget.every;

  @override
  void attached(WorldGame? previous) {
    // Ensure the component store exists.
    game.world.ensureObjectStore<T>();
    _dropMatch();
    _read(rebuild: false);
    _needsRead = false;
  }

  @override
  void didUpdateWidget(EntityBuilder<T, S> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.every != widget.every) _resetPolling();
    _dropMatch();
    // Read in build, after a simultaneous GameScope change has attached.
    _needsRead = true;
  }

  @override
  void frameTick() => _read(rebuild: true);

  void _dropMatch() {
    _matchQuery = null;
    _matched = null;
    _missRevision = -1;
  }

  T? _resolve() {
    final entity = widget.entity;
    if (entity != null) return game.world.tryGet<T>(entity);
    final query = _matchQuery ??= _buildMatchQuery();
    final matched = _matched;
    if (matched != null) {
      final component = query.get(matched);
      if (component != null) return component;
      _matched = null;
    }
    final revision = query.revision;
    if (revision == _missRevision) return null;
    final hit = query.firstOrNull;
    if (hit == null) {
      _missRevision = revision;
      return null;
    }
    _matched = hit.$1;
    _missRevision = -1;
    return hit.$2;
  }

  QueryView1<T> _buildMatchQuery() {
    final query = game.world.query<T>();
    final where = widget.where;
    return where == null ? query : where(query);
  }

  void _read({required bool rebuild}) {
    final component = _resolve();
    if (component == null) {
      final wasPresent = _selection != null;
      _selection = null;
      if (wasPresent && rebuild) setState(() {});
      return;
    }
    final value = widget.select(component);
    if (rebuild && (_selection?.matches(value) ?? false)) return;
    _selection = _Selection(value);
    if (rebuild) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (_needsRead) {
      _read(rebuild: false);
      _needsRead = false;
    }
    final selection = _selection;
    return selection != null
        ? widget.builder(context, selection.value)
        : (widget.absent ?? const SizedBox.shrink());
  }
}

/// Rebuilds when a selected world value changes.
class WorldBuilder<S> extends StatefulWidget {
  const WorldBuilder({
    super.key,
    required this.select,
    required this.builder,
    this.every,
  }) : trigger = null,
       duration = 0,
       pulseBuilder = null,
       child = null;

  /// The pulse form: the frame `trigger(previous, next)` passes,
  /// [pulseBuilder] receives 1.0, decaying to 0 over [duration] seconds of
  /// wall time.
  ///
  /// Widget updates refresh the selection baseline without firing a pulse.
  /// An active pulse survives parent rebuilds. Changing the game or switching
  /// between plain and pulse forms resets it; use a new key to reset it when
  /// reusing this widget for a different target within the same game.
  const WorldBuilder.pulse({
    super.key,
    required this.select,
    required bool Function(S previous, S next) this.trigger,
    required this.duration,
    required Widget Function(BuildContext context, double pulse, Widget? child)
    this.pulseBuilder,
    this.child,
  }) : builder = null,
       every = null,
       assert(
         duration > 0 && duration < double.infinity,
         'pulse duration is seconds and must be finite and positive',
       );

  /// Rebuilds when the selection changes: `==`, with lists, sets, maps, and
  /// iterables compared by contents, one level deep.
  final S Function(World world) select;

  /// Poll no more often than this, on wall time. Null runs [select] every
  /// frame. The escape hatch for a costly [select]; the value can be up to
  /// this stale. Widget updates and game changes refresh immediately.
  /// Zero reads every frame; negative intervals throw on mount or update.
  final Duration? every;

  /// Builds from the selected value. Frame ticks rebuild only on changes;
  /// parent rebuilds can also invoke this callback. Null in the pulse form.
  final Widget Function(BuildContext context, S value)? builder;

  /// Fires the pulse when a changed selection crosses this edge (pulse
  /// form; null in the plain form). Evaluated only when the selection changed.
  final bool Function(S previous, S next)? trigger;

  /// Seconds the pulse takes to decay 1 → 0, on wall time (pulse form).
  final double duration;

  /// Builds from the live pulse. Frame ticks request rebuilds while it decays;
  /// parent rebuilds can also invoke this callback, including at rest.
  /// Curving is the call site's job (`pulse * pulse`).
  final Widget Function(BuildContext context, double pulse, Widget? child)?
  pulseBuilder;

  /// Static subtree handed to [pulseBuilder] unrebuilt (the
  /// `AnimatedBuilder` convention).
  final Widget? child;

  @override
  State<WorldBuilder<S>> createState() => _WorldBuilderState<S>();
}

class _WorldBuilderState<S> extends _FrameTickState<WorldBuilder<S>> {
  late _Selection<S> _selection;
  double _pulse = 0;
  bool _needsRead = false;

  @override
  Duration? get pollInterval => widget.every;

  @override
  void _validateConfiguration() {
    super._validateConfiguration();
    if (widget.pulseBuilder != null &&
        (!widget.duration.isFinite || widget.duration <= 0)) {
      throw ArgumentError.value(
        widget.duration,
        'duration',
        'must be finite and positive',
      );
    }
  }

  @override
  void attached(WorldGame? previous) {
    _selection = _Selection(widget.select(game.world));
    _pulse = 0;
    _needsRead = false;
  }

  @override
  void didUpdateWidget(WorldBuilder<S> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.every != widget.every) _resetPolling();
    if ((oldWidget.pulseBuilder == null) != (widget.pulseBuilder == null)) {
      _pulse = 0;
    }
    // A new configuration establishes a baseline without firing a pulse.
    // Preserve an active pulse across ordinary parent rebuilds (including
    // recreated inline callbacks). A game or mode change resets it above.
    _needsRead = true;
  }

  @override
  void frameTick() {
    final value = widget.select(game.world);
    final previous = _selection;
    final same = previous.matches(value);
    final trigger = widget.trigger;
    if (trigger == null) {
      if (same) return;
      setState(() => _selection = _Selection(value));
      return;
    }
    final fired = !same && trigger(previous.snapshot, value);
    if (!same) _selection = _Selection(value);
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
    if (_needsRead) {
      _selection = _Selection(widget.select(game.world));
      _needsRead = false;
    }
    final pulseBuilder = widget.pulseBuilder;
    if (pulseBuilder != null) {
      return pulseBuilder(context, _pulse, widget.child);
    }
    return widget.builder!(context, _selection.value);
  }
}

/// Rebuilds when game state changes.
class GameStateBuilder<S extends Object> extends StatefulWidget {
  const GameStateBuilder({super.key, required this.builder});

  /// Builds for the active state value. Frame ticks rebuild on transitions;
  /// parent rebuilds can also invoke this callback.
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
  /// Callback failures are reported through [FlutterError.reportError];
  /// delivery continues with the remaining events and failed events are not
  /// retried. Events emitted by this callback reach this listener on a later
  /// frame.
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
    final reader = _reader;
    if (reader == null || !reader.hasUnread) return;
    // Consume the batch first, so callback failures cannot replay UI effects.
    // Snapshotting also keeps callback-emitted events for the next frame.
    for (final event in reader.drain()) {
      if (!mounted || !identical(_reader, reader)) break;
      try {
        widget.onEvent(context, event);
      } catch (error, stack) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stack,
            library: 'scene_dash_v2',
            context: ErrorDescription(
              'while delivering a $E event to WorldEventListener',
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
