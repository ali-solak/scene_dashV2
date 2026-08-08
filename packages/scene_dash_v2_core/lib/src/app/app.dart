import 'dart:async';

import '../diagnostics/app_diagnostics.dart';
import '../diagnostics/system_profiler.dart';
import '../entity/entity.dart';
import '../schedule/access_conflict.dart';
import '../schedule/schedule.dart';
import '../schedule/schedule_label.dart';
import '../schedule/schedule_runner.dart';
import '../schedule/schedules.dart';
import '../schedule/system_descriptor.dart';
import '../schedule/system_label.dart';
import '../schedule/system_registration.dart';
import '../schedule/system_set.dart';
import '../state/despawn_after.dart';
import '../state/states.dart';
import '../system/system_adapter.dart';
import '../world/world.dart';
import 'app_builder.dart';
import 'plugin.dart';

/// Runs a [World] through named schedules.
final class App implements AppBuilder {
  /// The ECS world this app operates on.
  final World world = World();

  final Map<ScheduleLabel, Schedule> _schedules = <ScheduleLabel, Schedule>{};
  final List<StateMachine> _stateMachines = <StateMachine>[];
  final Map<Type, Plugin> _addedPlugins = <Type, Plugin>{};
  final List<FutureOr<void> Function()> _cleanups =
      <FutureOr<void> Function()>[];

  /// How the app reacts to access conflicts between unordered systems.
  final AccessConflictPolicy accessConflictPolicy;

  /// Optional sink for diagnostics (e.g. access-conflict warnings). When the
  /// policy is [AccessConflictPolicy.warn], each conflict is passed here.
  final void Function(String message)? onDiagnostic;

  /// Access conflicts detected across all schedules during [start].
  final List<AccessConflict> accessConflicts = <AccessConflict>[];

  /// The system profiler, or null when profiling is disabled. When enabled it is
  /// also inserted as a `@Resource()` so overlays/systems can read it.
  final SystemProfiler? profiler;

  /// True once schedules have been compiled and frozen.
  bool _finalized = false;
  bool _shutdown = false;

  /// Event types whose reader-skip diagnostic has already been reported.
  final Set<Type> _reportedEventSkips = <Type>{};

  /// Schedules currently on the run stack, outermost first. Nesting is legal;
  /// re-entering one of these is a cycle.
  final List<ScheduleLabel> _running = <ScheduleLabel>[];

  /// Creates an app with the built-in schedules registered.
  App({
    this.accessConflictPolicy = AccessConflictPolicy.warn,
    this.onDiagnostic,
    AppDiagnostics diagnostics = const AppDiagnostics(),
  }) : profiler = _buildProfiler(diagnostics, onDiagnostic) {
    for (final label in Schedules.all) {
      _schedules[label] = Schedule(label);
    }
    // Lets systems dispatch a custom schedule through world.runSchedule
    // without reaching the app.
    world.resources.insert<ScheduleRunner>(ScheduleRunner(world, runSchedule));
    // Built-in runtime behavior, like the state-scoped despawn walk: entities
    // carrying DespawnAfter tick down each update and despawn at zero. Games
    // order against it with before/after on DespawnAfterSystem.label. Gated
    // on the store having rows so games that never use the component pay one
    // map lookup per pass and see nothing in system profiles.
    addSystemAdapter(
      DespawnAfterSystem(),
      schedule: Schedules.update,
      label: DespawnAfterSystem.label,
      runIf: (world) => world.ensureObjectStore<DespawnAfter>().length > 0,
    );
    final p = profiler;
    if (p != null) world.resources.insert<SystemProfiler>(p);
    final sink = onDiagnostic;
    if (sink != null) {
      // The accidental O(N×M) shape: a query iterated inside another
      // query's `each` in the same system. Detection runs only in debug
      // mode (the world's tracking sits inside asserts) and reports once
      // per system.
      world.onNestedQuery = sink;
      // Report dropped unread events once per type.
      world.onEventReaderSkip = (type, skipped) {
        if (!_reportedEventSkips.add(type)) return;
        sink(
          'An EventReader<$type> fell behind: $skipped unread event(s) '
          'expired past the channel retention window. This means a reader '
          'went longer than the window without a turn — usually a system '
          'gated by runIf, or a FIXED-step reader at a refresh rate high '
          'enough that render frames carry zero fixed steps. Widen the '
          'window with addEvent<$type>(retainedUpdates: ...) or pass null '
          'to retain events until every reader consumes them. (Reported '
          'once per event type.)',
        );
      };
    }
  }

  /// Builds the profiler from [diagnostics], routing slow-system warnings to the
  /// explicit sink or, failing that, the app's [onDiagnostic].
  static SystemProfiler? _buildProfiler(
    AppDiagnostics diagnostics,
    void Function(String message)? onDiagnostic,
  ) {
    if (!diagnostics.profileSystems) return null;
    final explicit = diagnostics.onSlowSystem;
    return SystemProfiler(
      slowSystemThreshold: diagnostics.slowSystemThreshold,
      onSlowSystem:
          explicit ??
          (onDiagnostic == null
              ? null
              : (event) => onDiagnostic(event.toString())),
    );
  }

  /// Registers an additional, custom schedule. Must be called before [start].
  void addSchedule(ScheduleLabel label) {
    _assertOpen();
    _schedules.putIfAbsent(label, () => Schedule(label));
  }

  @override
  AppBuilder addPlugin(Plugin plugin) {
    _assertOpen();
    final type = plugin.runtimeType;
    final existing = _addedPlugins[type];
    if (existing != null) {
      // Allow only the same instance twice.
      if (identical(existing, plugin)) return this;
      throw StateError(
        'A $type has already been added. Adding a second, different instance '
        'would be silently ignored along with its configuration; add each '
        'plugin exactly once.',
      );
    }
    for (final dependency in plugin.dependencies) {
      if (!_addedPlugins.containsKey(dependency)) {
        throw StateError(
          'Plugin $type requires $dependency, which has not been added. '
          'Add $dependency before $type.',
        );
      }
    }
    _addedPlugins[type] = plugin;
    plugin.build(this);
    return this;
  }

  @override
  AppBuilder addSystem(
    SystemDescriptor descriptor, {
    required ScheduleLabel schedule,
    List<SystemDescriptor> after = const <SystemDescriptor>[],
    List<SystemDescriptor> before = const <SystemDescriptor>[],
    RunCondition? runIf,
    SystemSet? inSet,
  }) {
    return addSystemAdapter(
      descriptor.buildAdapter(),
      schedule: schedule,
      label: descriptor.ref.label,
      after: <SystemLabel>[for (final d in after) d.ref.label],
      before: <SystemLabel>[for (final d in before) d.ref.label],
      runIf: runIf,
      inSet: inSet,
    );
  }

  @override
  AppBuilder addSystemAdapter(
    SystemAdapter adapter, {
    required ScheduleLabel schedule,
    required SystemLabel label,
    List<SystemLabel> after = const <SystemLabel>[],
    List<SystemLabel> before = const <SystemLabel>[],
    List<SystemLabel> independentOf = const <SystemLabel>[],
    RunCondition? runIf,
    SystemSet? inSet,
  }) {
    _assertOpen();
    final target = _scheduleFor(schedule);
    target.add(
      SystemRegistration(
        adapter: adapter,
        label: label,
        after: after,
        before: before,
        independentOf: independentOf,
        runIf: runIf,
        inSet: inSet,
      ),
    );
    return this;
  }

  @override
  AppBuilder configureSets(ScheduleLabel schedule, List<SystemSet> sets) {
    _assertOpen();
    _scheduleFor(schedule).configureSets(sets);
    return this;
  }

  Schedule _scheduleFor(ScheduleLabel schedule) {
    var target = _schedules[schedule];
    if (target == null && schedule is StateScheduleLabel) {
      // Create state schedules on demand.
      target = _schedules[schedule] = Schedule(schedule);
    }
    if (target == null) {
      throw StateError('Unknown schedule: ${schedule.id}');
    }
    return target;
  }

  @override
  AppBuilder addState<S extends Object>(S initial) {
    _assertOpen();
    if (world.resources.contains<CurrentState<S>>()) {
      throw StateError(
        'A state machine for $S has already been added. Each state type is '
        'registered exactly once; use a second enum for an orthogonal machine.',
      );
    }
    final machine = StateMachineRuntime<S>(initial);
    world.resources
      ..insert<CurrentState<S>>(machine.current)
      ..insert<NextState<S>>(machine.next);
    // Registered eagerly so game code can `commands.insert<DespawnOnExit>`
    // without any system having queried the type first.
    world.ensureObjectStore<DespawnOnExit>();
    _stateMachines.add(machine);
    return this;
  }

  @override
  AppBuilder addEvent<T>({int? retainedUpdates = 8}) {
    _assertOpen();
    world.registerEvent<T>(retainedUpdates: retainedUpdates);
    return this;
  }

  @override
  AppBuilder insertResource<T extends Object>(T resource) {
    _assertOpen();
    if (world.resources.contains<T>()) {
      throw StateError(
        'A resource of type $T is already inserted. Each resource should be '
        'owned by one place; call replaceResource<$T>() to intentionally swap '
        'it.',
      );
    }
    world.resources.insert<T>(resource);
    return this;
  }

  @override
  AppBuilder replaceResource<T extends Object>(T resource) {
    _assertOpen();
    world.resources.insert<T>(resource);
    return this;
  }

  @override
  AppBuilder addCleanup(FutureOr<void> Function() cleanup) {
    _assertOpen();
    _cleanups.add(cleanup);
    return this;
  }

  /// Compiles and freezes all schedules, initializes every system adapter,
  /// runs the [Schedules.startup] schedule once, then runs each state
  /// machine's `OnEnter(initial)`.
  ///
  /// [onStartupFlushed] runs before initial state entry.
  ///
  /// Transitions queued during startup or the initial enters are not applied
  /// here; they apply at the first [applyStateTransitions].
  void start({void Function()? onStartupFlushed}) {
    if (_finalized) {
      throw StateError('App has already been started.');
    }
    _validateStateSchedules();
    final detect = accessConflictPolicy != AccessConflictPolicy.ignore;
    for (final schedule in _schedules.values) {
      schedule.compile(world, detectConflicts: detect);
      accessConflicts.addAll(schedule.conflicts);
    }
    _reportAccessConflicts();
    _finalized = true;
    runSchedule(Schedules.startup);
    onStartupFlushed?.call();
    for (final machine in _stateMachines) {
      machine.enterInitial(_runStateSchedule);
    }
  }

  /// Rejects schedules for unregistered states.
  void _validateStateSchedules() {
    for (final label in _schedules.keys) {
      if (label is! StateScheduleLabel) continue;
      if (_stateMachines.any((machine) => machine.owns(label.value))) continue;
      throw StateError(
        'Systems are registered in ${label.id}, but no state machine covers '
        '${label.value}. Call addState<${label.value.runtimeType}>(...) '
        'before start().',
      );
    }
  }

  void _reportAccessConflicts() {
    if (accessConflicts.isEmpty) return;
    switch (accessConflictPolicy) {
      case AccessConflictPolicy.ignore:
        return;
      case AccessConflictPolicy.warn:
        final sink = onDiagnostic;
        if (sink != null) {
          for (final conflict in accessConflicts) {
            sink(conflict.toString());
          }
        }
      case AccessConflictPolicy.error:
        throw StateError(
          'Access conflicts detected between unordered systems:\n'
          '${accessConflicts.map((c) => '  - $c').join('\n')}',
        );
    }
  }

  /// Runs the named schedule, then flushes deferred commands.
  ///
  /// A system may run another schedule inline; the inner run completes (and
  /// flushes) before its caller resumes. Re-entering a schedule already on the
  /// stack is a cycle and throws rather than overflowing it.
  void runSchedule(ScheduleLabel label) {
    if (!_finalized) {
      throw StateError('Call start() before running schedules.');
    }
    final schedule = _schedules[label];
    if (schedule == null) {
      throw StateError('Unknown schedule: ${label.id}');
    }
    if (_running.contains(label)) {
      throw StateError(
        'Recursive schedule run: '
        '${[..._running, label].map((l) => l.id).join(' -> ')}. A schedule '
        'cannot run itself, directly or through another schedule.',
      );
    }
    _running.add(label);
    try {
      schedule.run(world, profiler);
      world.commands.apply();
    } finally {
      _running.removeLast();
    }
  }

  /// Applies pending state transitions for every registered state machine.
  ///
  /// Applies all queued state changes.
  ///
  /// The standard driver calls this at the frame-start boundary, after the
  /// [Schedules.frameStart] schedule; headless callers invoke it themselves at
  /// the equivalent point.
  void applyStateTransitions() {
    if (!_finalized) {
      throw StateError('Call start() before applying state transitions.');
    }
    if (_stateMachines.isEmpty) return;
    var passes = 0;
    while (true) {
      var applied = false;
      for (final machine in _stateMachines) {
        if (machine.applyPending(_runStateSchedule, _despawnStateScoped)) {
          applied = true;
        }
      }
      if (!applied) return;
      passes++;
      if (passes >= maxStateTransitionPasses) {
        throw StateError(
          'State transitions did not settle after $maxStateTransitionPasses '
          'passes — an OnEnter/OnExit system is queueing transitions in a '
          'cycle.',
        );
      }
    }
  }

  /// Chained-transition cap for one [applyStateTransitions] call.
  static const int maxStateTransitionPasses = 8;

  /// Runs a state lifecycle schedule if any system registered into it; a state
  /// value with no enter/exit systems is normal and skipped silently.
  void _runStateSchedule(ScheduleLabel label) {
    final schedule = _schedules[label];
    if (schedule == null) return;
    schedule.run(world, profiler);
    world.commands.apply();
  }

  /// Despawns every entity whose [DespawnOnExit] matches the state value being
  /// left. Runs after `OnExit(oldValue)` (whose commands have been flushed), so
  /// exit systems still see the entities and the buffer is safe to bypass.
  void _despawnStateScoped(Object oldValue) {
    final store = world.ensureObjectStore<DespawnOnExit>();
    if (store.length == 0) return;
    // Collect first: despawnNow compacts the store's dense rows as it removes.
    final doomed = <Entity>[];
    for (var dense = 0; dense < store.length; dense++) {
      if (store.valueAt(dense).value == oldValue) {
        doomed.add(world.entities.resolve(store.entityIndexAt(dense)));
      }
    }
    for (final entity in doomed) {
      world.despawnNow(entity);
    }
  }

  /// Advances all event channels, reclaiming consumed events. Call once per
  /// frame at a safe boundary (typically frame start).
  void updateEvents() => world.updateEvents();

  /// Runs shutdown and disposes resources.
  Future<void> shutdown() async {
    if (!_finalized || _shutdown) return;
    _shutdown = true;
    runSchedule(Schedules.shutdown);
    for (var i = _cleanups.length - 1; i >= 0; i--) {
      await _cleanups[i]();
    }
    world.resources.disposeAll();
  }

  void _assertOpen() {
    if (_finalized) {
      throw StateError(
        'The app is frozen; systems and schedules cannot be added after '
        'start().',
      );
    }
  }
}
