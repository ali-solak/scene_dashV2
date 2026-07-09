/// The global gameplay clock: scales or halts game time relative to wall
/// time. Hitstop, slow motion, and pause all reduce to this one resource.
///
/// A resource; inject it into systems with `@Resource()`. The standard driver
/// inserts one automatically and applies it at the frame-start boundary:
/// the raw wall-clock delta is multiplied by [effectiveScale] *before* it
/// reaches the scene tick, so component updates, animations, and the physics
/// accumulator all slow (or stop) together. Under slow motion the fixed
/// timestep itself is unchanged — fewer fixed steps run per wall second —
/// so `FixedTime.delta` stays the true step size and fixed-step gameplay
/// remains deterministic.
///
/// Systems that must keep moving while game time is stopped (HUD, camera
/// shake, pause menus) read `FrameTime.unscaledDelta` instead of
/// `FrameTime.delta`.
///
/// ```dart
/// @System()
/// void resolveHits(
///   @Resource() GameClock clock,
///   EventReader<HitEvent> hits,
/// ) {
///   for (final hit in hits.read()) {
///     clock.freezeFor(0.06); // hitstop: both sides freeze for 60ms
///   }
/// }
/// ```
final class GameClock {
  double _timeScale = 1.0;
  double _freezeRemaining = 0;

  /// Multiplier from wall time to game time: `1` is real time, `0.5` slow
  /// motion, `0` a hard stop. Negative values clamp to `0`.
  double get timeScale => _timeScale;
  set timeScale(double value) => _timeScale = value < 0 ? 0 : value;

  /// Hard gate on top of [timeScale]; while `true`, [effectiveScale] is `0`.
  ///
  /// Kept separate from [timeScale] so pausing preserves an in-progress
  /// slow-motion scale and unpausing restores it exactly.
  bool paused = false;

  /// Seconds of freeze left to serve, in wall time. `0` when not frozen.
  double get freezeRemaining => _freezeRemaining;

  /// Stops game time for the next [seconds] of wall time (hitstop).
  ///
  /// Does not stack: a request shorter than the freeze already in progress
  /// is absorbed by it, so overlapping hits extend the stop to the longest
  /// request rather than summing.
  void freezeFor(double seconds) {
    if (seconds > _freezeRemaining) _freezeRemaining = seconds;
  }

  /// The scale the driver applies this frame: `0` while [paused] or frozen,
  /// otherwise [timeScale].
  double get effectiveScale =>
      paused || _freezeRemaining > 0 ? 0.0 : _timeScale;

  /// Serves [unscaledDelta] wall seconds of an in-progress freeze. Driver
  /// API — the standard frame loop calls this once per frame, *after*
  /// reading [effectiveScale] (so a freeze shorter than one frame still
  /// freezes the frame it lands on); systems never call it.
  ///
  /// Freezes do not drain while [paused], so a hitstop taken into a pause
  /// menu resumes intact.
  void advanceFreeze(double unscaledDelta) {
    if (paused || _freezeRemaining == 0) return;
    _freezeRemaining -= unscaledDelta;
    if (_freezeRemaining < 0) _freezeRemaining = 0;
  }
}
