/// The global gameplay clock for pause, slow motion, and hitstop.
///
/// The standard driver applies [effectiveScale] before ticking the scene. Use
/// `FrameTime.unscaledDelta` for work that must continue while game time stops.
final class GameClock {
  double _timeScale = 1.0;
  double _freezeRemaining = 0;

  /// Multiplier from wall time to game time. Negative values clamp to zero.
  double get timeScale => _timeScale;
  set timeScale(double value) => _timeScale = value < 0 ? 0 : value;

  /// Hard gate on top of [timeScale].
  bool paused = false;

  /// Seconds of freeze left to serve, in wall time.
  double get freezeRemaining => _freezeRemaining;

  /// Stops game time for [seconds] of wall time. Overlapping requests keep the
  /// longer duration.
  void freezeFor(double seconds) {
    if (seconds > _freezeRemaining) _freezeRemaining = seconds;
  }

  /// The scale the driver applies this frame.
  double get effectiveScale =>
      paused || _freezeRemaining > 0 ? 0.0 : _timeScale;

  /// Advances an active freeze. The frame driver calls this once per frame.
  void advanceFreeze(double unscaledDelta) {
    if (paused || _freezeRemaining == 0) return;
    _freezeRemaining -= unscaledDelta;
    if (_freezeRemaining < 0) _freezeRemaining = 0;
  }
}
