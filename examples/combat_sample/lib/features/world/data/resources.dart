/// World-feature resources.
library;

import 'dart:math' as math;

/// Paces the surf against the cliff: a countdown (seconds until the next
/// break) that re-arms with jitter, and a seeded RNG so which point breaks
/// and when is deterministic. A resource only so it outlives the system.
class WaveClock {
  final math.Random rng = math.Random(19);
  double until = 0;
}

/// Accumulated ambient-wind phase, written each frame into the grass
/// material's `time` parameter.
class GrassWind {
  double time = 0;
}

/// The graphics preset in force, as an index into `qualityPresets`.
class GraphicsQuality {
  GraphicsQuality(this.level);

  /// Set by `applyGraphicsQuality` when it applies a preset; read by the
  /// menu to tick the active chip.
  int level;
}

/// Requests a quality preset.
final class QualityRequested {
  const QualityRequested(this.level);
  final int level;
}
