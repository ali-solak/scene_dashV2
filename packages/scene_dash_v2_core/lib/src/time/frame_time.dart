/// Per-frame timing, updated at the start of each rendered frame.
///
/// A resource; inject it into systems with `@Resource()`.
final class FrameTime {
  /// Seconds of *game time* elapsed since the previous frame: the wall-clock
  /// delta multiplied by the `GameClock`'s effective scale. `0` while the
  /// game is paused or in hitstop. This is the delta gameplay systems should
  /// integrate with.
  double delta = 0;

  /// Seconds of wall time elapsed since the previous frame, unaffected by
  /// the `GameClock`. For systems that keep moving while game time is
  /// stopped: HUD, camera shake, pause-menu effects.
  double unscaledDelta = 0;

  /// Total wall time elapsed since the app started.
  Duration elapsed = Duration.zero;

  /// Number of frames rendered so far.
  int frame = 0;
}
