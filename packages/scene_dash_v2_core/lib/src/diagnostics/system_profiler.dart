import '../schedule/schedule_label.dart';
import '../schedule/system_label.dart';

part 'system_timing.dart';

/// Emitted when a system's run exceeds the configured slow-system threshold.
final class SlowSystemEvent {
  const SlowSystemEvent({
    required this.timing,
    required this.elapsed,
    required this.frame,
  });

  /// The timing record for the system that ran slowly.
  final SystemTiming timing;

  /// How long this run took.
  final Duration elapsed;

  /// The frame number the slow run happened on.
  final int frame;

  @override
  String toString() {
    final ms = (elapsed.inMicroseconds / 1000).toStringAsFixed(2);
    return 'Slow system "${timing.debugName}" in schedule '
        '"${timing.schedule.id}" took $ms ms (frame $frame).';
  }
}

/// Collects execution timings per (system, schedule), keyed by stable
/// [SystemLabel] identity plus the [ScheduleLabel] it ran in — so a system
/// registered in more than one schedule keeps a separate record per schedule.
///
/// Profiling is opt-in (see `AppDiagnostics`) and adds no per-system work when
/// disabled. When enabled, the schedule measures each system with a single
/// reused [Stopwatch] and calls [record]; timing records are reused across frames
/// so steady-state profiling does not allocate.
///
/// The profiler is also inserted as a `@Resource()`, so a Flutter debug overlay
/// or a system can read [timings] to display per-system cost.
final class SystemProfiler {
  SystemProfiler({Duration? slowSystemThreshold, this.onSlowSystem})
    : _slowMicros = slowSystemThreshold?.inMicroseconds;

  /// Called when a run exceeds the slow-system threshold (if both are set).
  final void Function(SlowSystemEvent event)? onSlowSystem;

  final int? _slowMicros;

  /// A single reused stopwatch; the schedule resets and reads it per system.
  final Stopwatch stopwatch = Stopwatch();

  final Map<SystemLabel, Map<ScheduleLabel, SystemTiming>> _timings =
      <SystemLabel, Map<ScheduleLabel, SystemTiming>>{};

  int _frame = 0;

  /// The current frame number (advanced by [beginFrame]).
  int get frame => _frame;

  /// The configured slow-system threshold, if any.
  Duration? get slowSystemThreshold =>
      _slowMicros == null ? null : Duration(microseconds: _slowMicros);

  /// All recorded (system, schedule) timings (live view; do not mutate).
  Iterable<SystemTiming> get timings sync* {
    for (final bySchedule in _timings.values) {
      yield* bySchedule.values;
    }
  }

  /// The timing record for [system] in [schedule], or null if that pair has not
  /// run yet.
  SystemTiming? timingOf(SystemLabel system, ScheduleLabel schedule) =>
      _timings[system]?[schedule];

  /// Advances the frame counter. Called once per frame by the integration.
  void beginFrame() => _frame++;

  /// Clears all accumulated timings and resets the frame counter.
  void reset() {
    _timings.clear();
    _frame = 0;
  }

  /// Records one run of [label] (in [schedule]) that took [micros] microseconds.
  /// Reuses the per-(system, schedule) [SystemTiming] record.
  void record(SystemLabel label, ScheduleLabel schedule, int micros) {
    final bySchedule = _timings[label] ??= <ScheduleLabel, SystemTiming>{};
    final timing = bySchedule[schedule] ??= SystemTiming(
      label: label,
      debugName: _shortName(label.id),
      schedule: schedule,
    );
    timing._record(micros, _frame);

    final threshold = _slowMicros;
    if (threshold != null && micros >= threshold) {
      final sink = onSlowSystem;
      if (sink != null) {
        sink(
          SlowSystemEvent(
            timing: timing,
            elapsed: Duration(microseconds: micros),
            frame: _frame,
          ),
        );
      }
    }
  }

  /// Derives a short debug name from a `library#name` system-label id.
  static String _shortName(String id) {
    final hash = id.lastIndexOf('#');
    return hash < 0 ? id : id.substring(hash + 1);
  }
}
