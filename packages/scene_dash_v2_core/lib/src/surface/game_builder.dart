library;

import '../app/app.dart';
import '../app/plugin.dart';
import '../events/event_channel.dart';
import '../schedule/schedule_label.dart';
import '../schedule/schedules.dart';
import '../schedule/system_label.dart';
import '../schedule/system_registration.dart';
import '../schedule/system_set.dart';
import '../system/system_access.dart';
import '../system/system_adapter.dart';
import '../world/world.dart';
import 'observers.dart';

/// A system that updates the world.
typedef WorldSystem = void Function(World world);

/// Registers one game feature.
typedef Feature = void Function(GameBuilder game);

/// Registers game features.
final class GameBuilder {
  final App _app;

  /// Rejects systems without access declarations.
  final bool strictAccess;

  final Map<Function, SystemLabel> _labels = <Function, SystemLabel>{};
  int _sequence = 0;

  GameBuilder(this._app, {this.strictAccess = false});

  /// The world being configured.
  World get world => _app.world;

  /// Registers [system] into [schedule].
  ///
  /// [reads] and [writes] enable conflict checks.
  /// Systems in [before], [after], and [independentOf] must already exist.
  /// [independentOf] skips conflict checks for those systems.
  void addSystem(
    ScheduleLabel schedule,
    WorldSystem system, {
    Set<Type>? reads,
    Set<Type>? writes,
    List<WorldSystem> before = const <WorldSystem>[],
    List<WorldSystem> after = const <WorldSystem>[],
    List<WorldSystem> independentOf = const <WorldSystem>[],
    RunCondition? runIf,
    SystemSet? inSet,
    String? label,
  }) {
    final declared = reads != null || writes != null;
    if (strictAccess && !declared) {
      throw StateError(
        'addSystem(${_nameOf(system)}) is undeclared (no reads:/writes:) '
        'and this game booted with strictAccess: true. Declare the '
        'component types the system touches (or {} for none).',
      );
    }
    final systemLabel = _labelFor(system, label);
    // Fixed schedules use fixed time.
    final fixed = schedule == Schedules.fixedUpdate;
    final adapter = declared
        ? _DeclaredFunctionSystem(
            system,
            systemLabel,
            fixed,
            SystemAccess(
              reads: reads ?? const <Type>{},
              writes: writes ?? const <Type>{},
            ),
            _app.onDiagnostic,
          )
        : _FunctionSystem(system, systemLabel, fixed);
    RunCondition? condition = runIf;
    if (condition != null && fixed) {
      final inner = condition;
      condition = (World world) {
        final previous = world.fixedContext;
        world.fixedContext = true;
        try {
          return inner(world);
        } finally {
          world.fixedContext = previous;
        }
      };
    }
    _app.addSystemAdapter(
      adapter,
      schedule: schedule,
      label: systemLabel,
      before: [for (final s in before) _requireLabel(s, 'before')],
      after: [for (final s in after) _requireLabel(s, 'after')],
      independentOf: [
        for (final s in independentOf) _requireLabel(s, 'independentOf'),
      ],
      runIf: condition,
      inSet: inSet,
    );
  }

  /// Registers a custom schedule [label].
  ///
  /// Nothing drives it: run it with `world.runSchedule` (or the game's).
  void addSchedule(ScheduleLabel label) => _app.addSchedule(label);

  /// Configures the event channel for [T].
  void configureEvent<T extends Object>({int? retainedUpdates = 8}) =>
      world.registerEvent<T>(retainedUpdates: retainedUpdates);

  /// Orders [sets] within [schedule].
  void configureSets(ScheduleLabel schedule, List<SystemSet> sets) =>
      _app.configureSets(schedule, sets);

  /// Registers a plugin.
  void addPlugin(Plugin plugin) => _app.addPlugin(plugin);

  /// Registers state [S] with [initial].
  void addState<S extends Object>(S initial) => _app.addState<S>(initial);

  /// Runs [onAdd] and [onRemove] after [T] changes.
  ///
  /// Replacing [T] calls neither observer.
  /// Observers can queue commands and emit events.
  void observe<T extends Object>({
    ComponentObserver<T>? onAdd,
    ComponentObserver<T>? onRemove,
  }) => ObserverRegistry.of(world).observe<T>(onAdd: onAdd, onRemove: onRemove);

  /// Registers the component store for [T] up front, for types that only
  /// ever appear in spawn lists (never queried). Idempotent.
  void registerComponent<T extends Object>() => world.ensureObjectStore<T>();

  /// Registers the tag store for [T].
  void registerTag<T>() => world.ensureTagStore<T>();

  SystemLabel _labelFor(WorldSystem system, String? override) {
    final existing = _labels[system];
    if (existing != null) {
      // Keep one identity across schedules.
      return existing;
    }
    final label = SystemLabel(
      'system#${override ?? _nameOf(system)}@${_sequence++}',
    );
    _labels[system] = label;
    return label;
  }

  SystemLabel _requireLabel(WorldSystem system, String edge) {
    final label = _labels[system];
    if (label == null) {
      throw StateError(
        '$edge: [${_nameOf(system)}] references a system that has not been '
        'registered yet. Ordering edges are by function reference; register '
        'the referenced system first.',
      );
    }
    return label;
  }

  /// Finds a useful function name for logs.
  static String _nameOf(Function system) {
    final text = system.toString();
    final match = RegExp("from Function '([^']+)'").firstMatch(text);
    return match?.group(1) ?? 'closure';
  }
}

/// Stores event readers for one system.
abstract interface class EventCursorHost {
  /// Returns this system's reader for [T].
  EventReader<T> readerFor<T extends Object>(World world);

  /// Records queried component types.
  void noteQueriedTypes(List<Type> types);
}

/// Runs a system without conflict checks.
base class _FunctionSystem implements SystemAdapter, EventCursorHost {
  final WorldSystem _system;
  final SystemLabel _label;
  final bool _fixed;
  final Map<Type, EventReader<Object>> _readers = <Type, EventReader<Object>>{};
  World? _world;

  _FunctionSystem(this._system, this._label, this._fixed);

  @override
  void initialize(World world) => _world = world;

  @override
  void run() {
    final world = _world!;
    final previousSystem = world.runningSystem;
    final previousContext = world.fixedContext;
    world
      ..runningSystem = this
      ..fixedContext = _fixed;
    try {
      _system(world);
    } finally {
      world
        ..runningSystem = previousSystem
        ..fixedContext = previousContext;
    }
  }

  @override
  EventReader<T> readerFor<T extends Object>(World world) {
    final existing = _readers[T];
    if (existing != null) return existing as EventReader<T>;
    world.registerEvent<T>();
    // Include events sent before the first run.
    final reader = world.eventChannel<T>().readerFromStart();
    _readers[T] = reader;
    return reader;
  }

  @override
  void noteQueriedTypes(List<Type> types) {}

  @override
  String toString() => _label.id;
}

/// Runs a system with conflict checks.
final class _DeclaredFunctionSystem extends _FunctionSystem
    implements SystemAccessProvider {
  @override
  final SystemAccess access;

  final void Function(String message)? _diagnostics;
  Set<Type>? _driftReported;
  // Built once for debug query checks.
  late final Set<Type> _declared = <Type>{...access.reads, ...access.writes};

  _DeclaredFunctionSystem(
    super.system,
    super.label,
    super.fixed,
    this.access,
    this._diagnostics,
  );

  @override
  void noteQueriedTypes(List<Type> types) {
    assert(() {
      final sink = _diagnostics;
      if (sink == null) return true;
      final declared = _declared;
      for (final type in types) {
        if (declared.contains(type)) continue;
        final reported = _driftReported ??= <Type>{};
        if (!reported.add(type)) continue;
        sink(
          'Access drift: system "${_label.id}" queries $type but its '
          'reads:/writes: declaration does not mention it. Update the '
          'registration so the conflict detector sees the truth. '
          '(Debug-only check, reported once per type.)',
        );
      }
      return true;
    }());
  }
}
