part of 'system_profiler.dart';

/// A reusable, read-only timing record for a single (system, schedule) pair,
/// accumulated across frames.
///
/// One [SystemTiming] is created per (system, schedule) the first time it runs
/// under profiling and then updated in place by its owning [SystemProfiler] — the
/// profiler never allocates a fresh record per frame. Durations are stored as
/// microsecond integers (no [Duration] allocation on the hot path) and exposed
/// through [Duration] getters for display.
///
/// The counters are read-only to outside code: the profiler is exposed as a
/// `@Resource()`, so only it (in this library) may mutate the record.
final class SystemTiming {
  SystemTiming({
    required this.label,
    required this.debugName,
    required this.schedule,
  });

  /// The system's stable identity.
  final SystemLabel label;

  /// A short human-readable name for diagnostics (the declared system name).
  final String debugName;

  /// The schedule this system runs in.
  final ScheduleLabel schedule;

  int _runs = 0;
  int _totalMicros = 0;
  int _latestMicros = 0;
  int _maxMicros = 0;
  int _lastFrame = -1;

  /// Number of times the system has run.
  int get runs => _runs;

  /// Total time spent in the system, in microseconds.
  int get totalMicros => _totalMicros;

  /// Time spent in the most recent run, in microseconds.
  int get latestMicros => _latestMicros;

  /// The slowest single run observed, in microseconds.
  int get maxMicros => _maxMicros;

  /// The frame number of the most recent run (-1 until first run).
  int get lastFrame => _lastFrame;

  /// Total time spent in the system.
  Duration get total => Duration(microseconds: _totalMicros);

  /// Time spent in the most recent run.
  Duration get latest => Duration(microseconds: _latestMicros);

  /// The slowest single run observed.
  Duration get maximum => Duration(microseconds: _maxMicros);

  /// Mean time per run (zero before the first run).
  Duration get average => _runs == 0
      ? Duration.zero
      : Duration(microseconds: _totalMicros ~/ _runs);

  /// Accumulates one run. Library-private: only [SystemProfiler] calls this.
  void _record(int micros, int frame) {
    _runs += 1;
    _totalMicros += micros;
    _latestMicros = micros;
    if (micros > _maxMicros) _maxMicros = micros;
    _lastFrame = frame;
  }

  @override
  String toString() {
    final ms = (_latestMicros / 1000).toStringAsFixed(2);
    return '$debugName  $ms ms';
  }
}
