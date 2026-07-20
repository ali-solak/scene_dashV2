/// World-feature resources.
library;

/// Accumulated wind-phase time, written each frame into the grass material's
/// `time` parameter. A resource (not a system-local) so the wind dramaturgy
/// can read and shape the same phase.
class GrassWind {
  double time = 0;
}

/// The wind's dramaturgy (task 18), written by the encounter and read by
/// the grass material: gusts while the barbarians circle, near-still while
/// one telegraphs (the held breath before a swing). A resource so the
/// grass (world) reads what the fight (rules) writes without either
/// importing the other.
class WindState {
  /// Multiplier on the base grass wind strength (eased toward its target).
  double strength = 1;
}
