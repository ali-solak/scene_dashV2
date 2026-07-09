/// A tiny, dependency-free benchmark harness.
///
/// Reports nanoseconds per "op" (an op is whatever unit you pass as
/// [opsPerRun] — typically one entity processed), so results across
/// different entity counts are comparable. It is deliberately simple; treat
/// the numbers as relative signals on this machine, not absolute truth, and
/// always validate on a representative release-mode target before claiming a
/// performance result.
library;

/// One benchmark measurement.
class BenchResult {
  final String name;
  final double nsPerOp;
  final int runs;

  BenchResult(this.name, this.nsPerOp, this.runs);
}

double _nsOf(Stopwatch sw) => sw.elapsedTicks * 1e9 / sw.frequency;

/// Benchmarks [run] over reusable state (no per-run setup). Use for read-only
/// work such as query iteration. [opsPerRun] is the number of ops one [run]
/// performs (e.g. the entity count).
BenchResult benchRepeat(
  String name,
  int opsPerRun,
  void Function() run, {
  Duration minTime = const Duration(milliseconds: 400),
  int warmup = 5,
}) {
  for (var i = 0; i < warmup; i++) {
    run();
  }
  final sw = Stopwatch()..start();
  var runs = 0;
  var totalNs = 0.0;
  while (sw.elapsed < minTime) {
    final timer = Stopwatch()..start();
    run();
    timer.stop();
    totalNs += _nsOf(timer);
    runs++;
  }
  sw.stop();
  final result = BenchResult(name, totalNs / (runs * opsPerRun), runs);
  _print(result);
  return result;
}

/// Benchmarks [run] with fresh [setup] state per timed run (the setup is not
/// timed). Use for structural mutations such as spawning or despawning.
BenchResult benchSetup<T>(
  String name,
  int opsPerRun, {
  required T Function() setup,
  required void Function(T state) run,
  Duration minTime = const Duration(milliseconds: 400),
  int warmup = 5,
}) {
  for (var i = 0; i < warmup; i++) {
    run(setup());
  }
  final overall = Stopwatch()..start();
  var runs = 0;
  var totalNs = 0.0;
  while (overall.elapsed < minTime) {
    final state = setup();
    final timer = Stopwatch()..start();
    run(state);
    timer.stop();
    totalNs += _nsOf(timer);
    runs++;
  }
  overall.stop();
  final result = BenchResult(name, totalNs / (runs * opsPerRun), runs);
  _print(result);
  return result;
}

void _print(BenchResult r) {
  final ns = r.nsPerOp;
  final perOp = ns >= 1000
      ? '${(ns / 1000).toStringAsFixed(2)} us/op'
      : '${ns.toStringAsFixed(2)} ns/op';
  print('  ${r.name.padRight(38)} $perOp');
}

/// Prints a header for a benchmark group.
void section(String title, {int? entities}) {
  final suffix = entities == null ? '' : '  (N = $entities)';
  print('\n=== $title$suffix ===');
}

/// Parses an optional entity count from argv (default [fallback]).
int entityCount(List<String> args, {int fallback = 10000}) {
  if (args.isEmpty) return fallback;
  return int.tryParse(args.first) ?? fallback;
}
