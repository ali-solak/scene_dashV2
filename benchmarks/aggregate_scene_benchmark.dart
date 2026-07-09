// Aggregates captured examples/scene_benchmark output.
//
// Usage:
//   dart run aggregate_scene_benchmark.dart results/run1.txt results/run2.txt
//   dart run aggregate_scene_benchmark.dart results/
//
// The parser reads `SCENE_BENCHMARK result ...` lines and groups them by
// benchmark mode plus profileSystems setting.
import 'dart:io';
import 'dart:math' as math;

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln(
      'Usage: dart run aggregate_scene_benchmark.dart <file-or-dir> [...]',
    );
    exitCode = 64;
    return;
  }

  final files = <File>[];
  for (final arg in args) {
    final type = FileSystemEntity.typeSync(arg);
    switch (type) {
      case FileSystemEntityType.file:
        files.add(File(arg));
      case FileSystemEntityType.directory:
        files.addAll(
          Directory(arg)
              .listSync(recursive: true)
              .whereType<File>()
              .where((file) => file.path.endsWith('.txt')),
        );
      case FileSystemEntityType.notFound:
      case FileSystemEntityType.link:
        stderr.writeln('Skipping non-file path: $arg');
    }
  }

  final groups = <String, List<_Run>>{};
  for (final file in files) {
    final content = file.readAsStringSync().replaceAll('\u0000', '');
    for (final rawLine in content.split(RegExp(r'\r?\n'))) {
      final start = rawLine.indexOf('SCENE_BENCHMARK result ');
      if (start < 0) continue;
      final line = rawLine.substring(start);
      final values = _parseKeyValues(line);
      final mode = values['mode'];
      final profileSystems = values['profileSystems'] ?? 'false';
      if (mode == null) continue;
      final run = _Run(
        buildMedian: double.parse(values['build_median_ms']!),
        buildP95: double.parse(values['build_p95_ms']!),
        rasterMedian: double.parse(values['raster_median_ms']!),
        rasterP95: double.parse(values['raster_p95_ms']!),
      );
      (groups['$mode profileSystems=$profileSystems'] ??= <_Run>[]).add(run);
    }
  }

  if (groups.isEmpty) {
    stderr.writeln('No SCENE_BENCHMARK result lines found.');
    exitCode = 1;
    return;
  }

  final keys = groups.keys.toList()..sort();
  for (final key in keys) {
    final runs = groups[key]!;
    stdout.writeln(key);
    stdout.writeln('  runs: ${runs.length}');
    _printMetric('build median', runs.map((r) => r.buildMedian).toList());
    _printMetric('build p95', runs.map((r) => r.buildP95).toList());
    _printMetric('raster median', runs.map((r) => r.rasterMedian).toList());
    _printMetric('raster p95', runs.map((r) => r.rasterP95).toList());
    stdout.writeln();
  }
}

Map<String, String> _parseKeyValues(String line) {
  final values = <String, String>{};
  for (final token in line.split(' ')) {
    final equals = token.indexOf('=');
    if (equals <= 0) continue;
    values[token.substring(0, equals)] = token.substring(equals + 1);
  }
  return values;
}

void _printMetric(String label, List<double> values) {
  values.sort();
  final min = values.first;
  final max = values.last;
  final median = _percentile(values, 0.50);
  final stddev = _stddev(values);
  stdout.writeln('  $label median-of-runs: ${_fmt(median)} ms');
  stdout.writeln('  $label range: ${_fmt(min)}-${_fmt(max)} ms');
  stdout.writeln('  $label stddev: ${_fmt(stddev)} ms');
}

double _percentile(List<double> sorted, double p) {
  if (sorted.isEmpty) return 0;
  final raw = (sorted.length - 1) * p;
  final low = raw.floor();
  final high = raw.ceil();
  if (low == high) return sorted[low];
  final t = raw - low;
  return sorted[low] * (1 - t) + sorted[high] * t;
}

double _stddev(List<double> values) {
  if (values.length < 2) return 0;
  final mean = values.reduce((a, b) => a + b) / values.length;
  final variance = values.map((value) {
        final delta = value - mean;
        return delta * delta;
      }).reduce((a, b) => a + b) /
      values.length;
  return math.sqrt(variance);
}

String _fmt(double value) => value.toStringAsFixed(3);

final class _Run {
  const _Run({
    required this.buildMedian,
    required this.buildP95,
    required this.rasterMedian,
    required this.rasterP95,
  });

  final double buildMedian;
  final double buildP95;
  final double rasterMedian;
  final double rasterP95;
}
