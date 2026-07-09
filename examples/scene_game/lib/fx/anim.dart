/// Tiny animation-easing helpers shared across features.
library;

/// Moves [value] toward [target] by the eased [rate] (clamped to `[0, 1]`),
/// the standard "exponential approach" for show/hide and follow factors.
/// Callers pass `dt * speed` as the rate, so the ease is frame-rate aware.
double approach(double value, double target, double rate) {
  final a = rate.clamp(0.0, 1.0).toDouble();
  return value + (target - value) * a;
}
