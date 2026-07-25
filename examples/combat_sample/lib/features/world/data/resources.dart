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

/// Accumulated wind-phase time, written each frame into the grass material's
/// `time` parameter. A resource (not a system-local) so the wind dramaturgy
/// can read and shape the same phase.
class GrassWind {
  double time = 0;
}

/// Wind strength for the grass material: gusts while the barbarians
/// circle, near-still while one telegraphs. A resource so the grass
/// (world) reads what the fight (rules) writes without either importing
/// the other.
class WindState {
  /// Multiplier on the base grass wind strength (eased toward its target).
  double strength = 1;
}

/// The graphics preset in force, as an index into `qualityPresets`.
class GraphicsQuality {
  GraphicsQuality(this.level);

  /// Set by `applyGraphicsQuality` when it applies a preset; read by the
  /// menu to tick the active chip.
  int level;
}

/// Menu intent: switch to `qualityPresets[level]`.
///
/// An event rather than a direct write, for the same reason buying a
/// skill is one: widgets ask, systems decide. It keeps one write path
/// into the world even for a setting with no rules to enforce.
final class QualityRequested {
  const QualityRequested(this.level);
  final int level;
}
