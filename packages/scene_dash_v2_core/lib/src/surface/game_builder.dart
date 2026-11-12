library;

import 'dart:collection';

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

typedef SystemEntry = (WorldSystem, {Set<Type> reads, Set<Type> writes});

/// Registers game features.
final class GameBuilder {
  final App _app;

  /// Rejects systems without access declarations.
  final bool strictAccess;

  final _SharedLabels _shared;
  final RunCondition? _groupRunIf;
  final SystemSet? _groupSet;

  GameBuilder(this._app, {this.strictAccess = false})
    : _shared = _SharedLabels(),
      _groupRunIf = null,
      _groupSet = null;

  GameBuilder._group(
    this._app,
    this.strictAccess,
    this._shared,
    this._groupRunIf,
    this._groupSet,
  );

  void group(
    void Function(GameBuilder game) register, {
    RunCondition? runIf,
    SystemSet? inSet,
  }) {
    register(
      GameBuilder._group(
        _app,
        strictAccess,
        _shared,
        _both(_groupRunIf, runIf),
        _setFor(inSet, 'group'),
      ),
    );
  }

  static RunCondition? _both(RunCondition? outer, RunCondition? inner) {
    if (outer == null) return inner;
    if (inner == null) return outer;
    return (World world) => outer(world) && inner(world);
  }

  SystemSet? _setFor(SystemSet? own, String site) {
    final shared = _groupSet;
    if (own == null) return shared;
    if (shared != null && shared != own) {
      throw ArgumentError(
        '$site(inSet: $own) inside a group(inSet: $shared). A system belongs '
        'to one set; drop one of the two.',
      );
    }
    return own;
  }

  /// The world being configured.
  World get world => _app.world;

  /// Registers [system] into [schedule].
  ///
  /// [reads] and [writes] enable conflict checks.
  /// Systems in [before], [after], and [independentOf] can be registered
  /// later. References are resolved when the app starts and must name systems
  /// in the same schedule.
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
    final systemLabel = _labelFor(system, label, schedule);
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
    var condition = _both(_groupRunIf, runIf);
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
      before: _DeferredSystemLabels(before, (s) => _requireLabel(s, 'before')),
      after: _DeferredSystemLabels(after, (s) => _requireLabel(s, 'after')),
      independentOf: _DeferredSystemLabels(
        independentOf,
        (s) => _requireLabel(s, 'independentOf'),
      ),
      runIf: condition,
      inSet: _setFor(inSet, 'addSystem(${systemLabel.id})'),
    );
    _app.addCleanup(adapter.disposeReaders);
  }

  void addSystems(
    ScheduleLabel schedule,
    List<SystemEntry> systems, {
    RunCondition? runIf,
    SystemSet? inSet,
    bool chain = false,
  }) {
    WorldSystem? previous;
    for (final (system, :reads, :writes) in systems) {
      addSystem(
        schedule,
        system,
        reads: reads,
        writes: writes,
        after: chain && previous != null ? [previous] : const <WorldSystem>[],
        runIf: runIf,
        inSet: inSet,
      );
      previous = system;
    }
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

  SystemLabel _labelFor(
    WorldSystem system,
    String? override,
    ScheduleLabel schedule,
  ) {
    final existing = _shared.labels[system];
    if (existing != null) return existing;
    final name = override ?? _nameOf(system);
    final label = SystemLabel('system#$name@${_shared.sequence++}');
    _shared.labels[system] = label;
    if (override == null && name == 'closure') _warnUnnamed(label, schedule);
    return label;
  }

  void _warnUnnamed(SystemLabel label, ScheduleLabel schedule) {
    if (_shared.warnedUnnamed) return;
    final sink = _app.onDiagnostic;
    if (sink == null) return;
    _shared.warnedUnnamed = true;
    sink(
      'System ${label.id} in $schedule has no readable name: it is a closure, '
      'or this is a web or obfuscated build where function names are not '
      'available. Diagnostics, profiles and conflict reports will show it as '
      'closure@N. Pass label: to addSystem for a stable name. (Reported once.)',
    );
  }

  SystemLabel _requireLabel(WorldSystem system, String edge) {
    final label = _shared.labels[system];
    if (label == null) {
      throw StateError(
        '$edge: [${_nameOf(system)}] references a system that has not been '
        'registered. Ordering edges use function references; install the '
        'feature that registers this function before starting the game.',
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

final class _SharedLabels {
  final Map<Function, SystemLabel> labels = <Function, SystemLabel>{};
  int sequence = 0;
  bool warnedUnnamed = false;
}

/// A snapshot of function references, resolved by the schedule compiler after
/// all features have installed. Late explicit labels are preserved.
final class _DeferredSystemLabels extends ListBase<SystemLabel> {
  _DeferredSystemLabels(List<WorldSystem> systems, this.resolve)
    : _systems = List.of(systems);

  final List<WorldSystem> _systems;
  final SystemLabel Function(WorldSystem) resolve;

  @override
  int get length => _systems.length;
  @override
  set length(int value) =>
      throw UnsupportedError('Immutable system references');
  @override
  SystemLabel operator [](int index) => resolve(_systems[index]);
  @override
  void operator []=(int index, SystemLabel value) =>
      throw UnsupportedError('Immutable system references');
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

  void disposeReaders() {
    for (final reader in _readers.values) {
      reader.dispose();
    }
    _readers.clear();
  }

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
