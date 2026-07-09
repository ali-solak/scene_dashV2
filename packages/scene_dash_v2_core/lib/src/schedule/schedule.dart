import '../diagnostics/system_profiler.dart';
import '../world/world.dart';
import 'access_conflict.dart';
import 'schedule_graph.dart';
import 'schedule_label.dart';
import 'system_registration.dart';
import 'system_set.dart';

/// One named phase of the frame: an ordered collection of systems.
///
/// Systems are added during plugin build. At startup the schedule is [compile]d
/// once (topologically sorted and frozen); after that, [run] executes the
/// systems in their compiled order. Registration after compilation is rejected.
final class Schedule {
  /// The label identifying this schedule.
  final ScheduleLabel label;

  final List<SystemRegistration> _registrations = <SystemRegistration>[];
  final List<List<SystemSet>> _setChains = <List<SystemSet>>[];
  List<SystemRegistration>? _compiled;

  /// Access conflicts detected between unordered systems during [compile].
  final List<AccessConflict> conflicts = <AccessConflict>[];

  Schedule(this.label);

  /// Whether this schedule has been compiled (and is therefore frozen).
  bool get isCompiled => _compiled != null;

  /// Number of systems registered.
  int get systemCount => _registrations.length;

  /// Adds a system registration. Throws if the schedule is already frozen.
  void add(SystemRegistration registration) {
    if (isCompiled) {
      throw StateError(
        'Cannot register systems in schedule "${label.id}" after it is '
        'compiled.',
      );
    }
    _registrations.add(registration);
  }

  /// Declares that the members of each set in [sets] run before the members
  /// of every later set in the list. Expanded to member-level `after` edges
  /// at [compile]. Throws if the schedule is already frozen.
  void configureSets(List<SystemSet> sets) {
    if (isCompiled) {
      throw StateError(
        'Cannot configure sets in schedule "${label.id}" after it is '
        'compiled.',
      );
    }
    _setChains.add(List<SystemSet>.unmodifiable(sets));
  }

  /// Topologically sorts and freezes the schedule, then initializes every
  /// system adapter against [world].
  ///
  /// When [detectConflicts] is true, [conflicts] is populated with any
  /// access conflicts between unordered systems.
  void compile(World world, {bool detectConflicts = true}) {
    final result = ScheduleGraph.compile(
      label,
      _registrations,
      setChains: _setChains,
      detectConflicts: detectConflicts,
    );
    for (final registration in result.ordered) {
      registration.adapter.initialize(world);
    }
    conflicts
      ..clear()
      ..addAll(result.conflicts);
    _compiled = result.ordered;
  }

  /// Runs every system in compiled order. Must be compiled first.
  ///
  /// A system with a `runIf` condition is skipped for this pass when the
  /// condition returns `false`; [world] is what conditions read.
  ///
  /// When [profiler] is non-null, each system that runs is timed with the
  /// profiler's reused stopwatch and recorded under this schedule's label. The
  /// null-profiler path is the unchanged tight loop, so profiling adds nothing
  /// when disabled.
  void run(World world, [SystemProfiler? profiler]) {
    final compiled = _compiled;
    if (compiled == null) {
      throw StateError('Schedule "${label.id}" has not been compiled.');
    }
    if (profiler == null) {
      for (var i = 0; i < compiled.length; i++) {
        final registration = compiled[i];
        final condition = registration.runIf;
        if (condition != null && !condition(world)) continue;
        registration.adapter.run();
      }
      return;
    }
    final stopwatch = profiler.stopwatch;
    for (var i = 0; i < compiled.length; i++) {
      final registration = compiled[i];
      final condition = registration.runIf;
      if (condition != null && !condition(world)) continue;
      stopwatch
        ..reset()
        ..start();
      registration.adapter.run();
      stopwatch.stop();
      profiler.record(registration.label, label, stopwatch.elapsedMicroseconds);
    }
  }
}
