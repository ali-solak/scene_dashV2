part of '../decor.dart';

const int _moteCount = 48;
const double _moteAmplitude = 0.6;

/// Feature-owned state for the motes: the per-mote scene nodes (built at
/// startup) plus packed per-mote animation data.
final class MoteField {
  /// Built by `spawnMotes`; empty until then (and forever in a headless
  /// game).
  final List<Node> motes = [];

  /// Base position (x, y, z) per mote, packed; `3 * _moteCount` long.
  final Float32List base = Float32List(_moteCount * 3);

  /// Per-mote bob phase and speed.
  final Float32List phase = Float32List(_moteCount);
  final Float32List speed = Float32List(_moteCount);
}
