/// The registration surface features write against: plain functions over
/// the carried v1 machinery.
///
/// A system is a stateless `void Function(World)`; [addSystem] wraps it in
/// an internal adapter, builds its `SystemAccess` from `reads:`/`writes:`
/// (§1.8 of the design), and reaches every carried scheduling capability —
/// labels, `before:`/`after:` (by function reference), sets, run
/// conditions, `OnEnter`/`OnExit` — unchanged.
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

/// A system: stateless, world-in. All state lives in the world; event
/// cursors are managed per registration by the framework.
typedef WorldSystem = void Function(World world);

/// A feature: a plain function over the builder — v1's plugin body without
/// the class.
typedef Feature = void Function(GameBuilder game);

/// What features register against — the one builder (D12): v1's
/// `AppBuilder` with the new surface folded in as members. Everything a
/// feature could want is a member here; there is no inner builder to
/// reach through. `SceneGame` and `TestGame` construct one and hand it to
/// each feature.
final class GameBuilder {
  final App _app;

  /// When true, a system registered without `reads:`/`writes:` is a boot
  /// error instead of being silently excluded from conflict detection
  /// (§1.8).
  final bool strictAccess;

  final Map<Function, SystemLabel> _labels = <Function, SystemLabel>{};
  int _sequence = 0;

  GameBuilder(this._app, {this.strictAccess = false});

  /// The world being configured.
  World get world => _app.world;

  /// Registers [system] into [schedule].
  ///
  /// [reads]/[writes] declare the component types the system touches; they
  /// feed the existing startup conflict detector. Omitting both marks the
  /// system *undeclared* — excluded from detection (and rejected when
  /// [strictAccess]). In debug mode, declared access is compared against
  /// the component types the system's queries actually construct, and
  /// drift is reported once through the app's diagnostics sink.
  ///
  /// [before]/[after] order against other systems *by function reference*
  /// — register the referenced system first. [runIf], [inSet] and the
  /// schedule labels are the carried machinery.
  void addSystem(
    ScheduleLabel schedule,
    WorldSystem system, {
    Set<Type>? reads,
    Set<Type>? writes,
    List<WorldSystem> before = const <WorldSystem>[],
    List<WorldSystem> after = const <WorldSystem>[],
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
    // Fixed schedules flip the world's fixed context for the body and its
    // run condition, so `world.dt` and `every()` pick the right delta
    // (D7, D9). State lifecycle schedules run at the frame boundary:
    // frame context.
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
      runIf: condition,
      inSet: inSet,
    );
  }

  /// Tunes the event channel for [T] before boot — the carried
  /// `addEvent(retainedUpdates:)`. Channels otherwise auto-register with
  /// the default retention on first `emit`/`events<T>()`.
  void configureEvent<T extends Object>({int? retainedUpdates = 8}) =>
      world.registerEvent<T>(retainedUpdates: retainedUpdates);

  /// Declares the order of [sets] within [schedule], once per schedule —
  /// the cross-feature phase list. Features join a phase with `inSet:` on
  /// [addSystem] and never reference each other's systems.
  void configureSets(ScheduleLabel schedule, List<SystemSet> sets) =>
      _app.configureSets(schedule, sets);

  /// Registers a classic plugin — the migration escape hatch.
  void addPlugin(Plugin plugin) => _app.addPlugin(plugin);

  /// Registers a state machine for [S] starting at [initial] — the carried
  /// v1 machinery; systems register into `OnEnter(value)`/`OnExit(value)`
  /// through [addSystem].
  void addState<S extends Object>(S initial) => _app.addState<S>(initial);

  /// Registers component observers for [T]: [onAdd] fires when an entity
  /// gains a [T], [onRemove] when it loses one — [onRemove] receives the
  /// still-live removed instance. Explicit and per feature; multiple
  /// observers per type fire in registration order.
  ///
  /// Observers fire during the command-boundary flush, immediately after
  /// the individual change applies, identically on device and under
  /// `TestGame` (S1). Despawn strips components, so [onRemove] fires for
  /// each observed component the entity carried — the "react to Health
  /// removed" pattern is intended, not incidental (S3). Adding a component
  /// the entity already has replaces the value, refreshes any
  /// `removeAfter:` deadline, and fires **nothing**; there is no
  /// `onChange`, deliberately — in-place object mutation makes honest
  /// change marking impossible (S4).
  ///
  /// Observer bodies may use the deferred verbs (`add`, `remove`, `spawn`,
  /// `despawn` — they land in the same flush) and `world.emit`, but not
  /// `world.events<T>()`: observers have no registration cursor, so
  /// observers emit and systems read (S5). Observers sit outside the
  /// `reads:`/`writes:` conflict model, like resources — declare what your
  /// *systems* touch; observer access is not detected. An observer
  /// re-adding or re-removing what it observes loops the flush; a
  /// debug-mode guard trips after 16 firings of one type per flush (S6).
  void observe<T extends Object>({
    ComponentObserver<T>? onAdd,
    ComponentObserver<T>? onRemove,
  }) => ObserverRegistry.of(world).observe<T>(onAdd: onAdd, onRemove: onRemove);

  /// Registers the component store for [T] up front, for types that only
  /// ever appear in spawn lists (never queried). Idempotent.
  void registerComponent<T extends Object>() => world.ensureObjectStore<T>();

  /// Registers the tag store for [T]. Tags always need this — a tag store
  /// cannot be created from a spawned instance. Idempotent.
  void registerTag<T>() => world.ensureTagStore<T>();

  SystemLabel _labelFor(WorldSystem system, String? override) {
    final existing = _labels[system];
    if (existing != null) {
      // The same function in a second schedule keeps one identity (the
      // profiler records per (label, schedule)).
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

  /// Best-effort function name for labels and messages, parsed from the
  /// closure's `toString` (`... from Function 'updateProjectiles': ...`);
  /// anonymous closures fall back to their type.
  static String _nameOf(Function system) {
    final text = system.toString();
    final match = RegExp("from Function '([^']+)'").firstMatch(text);
    return match?.group(1) ?? 'closure';
  }
}

/// The per-registration state behind `world.events<T>()`: memoized readers
/// keyed by event type, owned by the registration so a system re-entering
/// keeps its cursor.
abstract interface class EventCursorHost {
  /// The registration's reader for [T], created (at the channel end) on
  /// first use.
  EventReader<T> readerFor<T extends Object>(World world);

  /// Debug bookkeeping: a record query constructed under this system noted
  /// the component types it touches.
  void noteQueriedTypes(List<Type> types);
}

/// An undeclared function system: runs the function with the
/// current-system hook set; contributes nothing to conflict detection.
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
    // From the channel start, so events emitted just before this
    // registration's first run are not missed.
    final reader = world.eventChannel<T>().readerFromStart();
    _readers[T] = reader;
    return reader;
  }

  @override
  void noteQueriedTypes(List<Type> types) {}

  @override
  String toString() => _label.id;
}

/// A declared function system: additionally carries its hand-written
/// [SystemAccess] for the conflict detector, and (in debug mode) warns once
/// when the queries it actually constructs drift from the declaration.
final class _DeclaredFunctionSystem extends _FunctionSystem
    implements SystemAccessProvider {
  @override
  final SystemAccess access;

  final void Function(String message)? _diagnostics;
  Set<Type>? _driftReported;
  // Built once: noteQueriedTypes runs per query construction per frame in
  // debug mode, so the declared set must not be rebuilt per call.
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
