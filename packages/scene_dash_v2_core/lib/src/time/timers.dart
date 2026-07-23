/// Mutable timer value types driven by an explicit `tick(dt)`.
library;

/// Counts up to a duration, reporting completion once or repeatedly.
///
/// A one-shot timer stays finished until [reset]. Repeating timers preserve
/// overshoot and report every completion in a long frame through
/// [completionsThisTick].
final class GameTimer {
  /// The target duration in seconds.
  double duration;

  /// Whether the timer restarts itself on completion.
  final bool repeating;

  double _elapsed = 0;
  bool _justFinished = false;
  int _completionsThisTick = 0;

  /// A one-shot timer.
  GameTimer(this.duration) : repeating = false;

  /// A repeating timer. [duration] must be positive.
  GameTimer.repeating(this.duration)
    : repeating = true,
      assert(duration > 0, 'A repeating GameTimer needs a positive duration.');

  /// Seconds accumulated toward the current period.
  double get elapsed => _elapsed;

  /// Whether the timer is finished. Repeating timers are finished only on the
  /// tick that completes a period.
  bool get finished =>
      repeating ? _justFinished : duration <= 0 || _elapsed >= duration;

  /// Whether the most recent [tick] completed the timer.
  bool get justFinished => _justFinished;

  /// Periods completed by the most recent [tick].
  int get completionsThisTick => _completionsThisTick;

  /// Progress through the current period in `[0, 1]`.
  double get fraction {
    if (duration <= 0) return 1;
    final f = _elapsed / duration;
    return f < 0 ? 0 : (f > 1 ? 1 : f);
  }

  /// Seconds left in the current period.
  double get remaining {
    final r = duration - _elapsed;
    return r < 0 ? 0 : r;
  }

  /// Advances the timer by [delta] seconds.
  void tick(double delta) {
    _justFinished = false;
    _completionsThisTick = 0;
    if (!repeating) {
      if (_elapsed >= duration) return;
      _elapsed += delta;
      if (_elapsed >= duration) {
        _elapsed = duration;
        _justFinished = true;
        _completionsThisTick = 1;
      }
      return;
    }
    _elapsed += delta;
    if (_elapsed >= duration) {
      // Avoid looping after a long frame.
      final periods = _elapsed ~/ duration;
      _elapsed -= periods * duration;
      _completionsThisTick = periods;
      _justFinished = true;
    }
  }

  /// Restarts the timer. Pass [duration] to change its target.
  void reset([double? duration]) {
    if (duration != null) this.duration = duration;
    _elapsed = 0;
    _justFinished = false;
    _completionsThisTick = 0;
  }
}

/// Counts up without a target.
final class GameStopwatch {
  double _elapsed = 0;

  /// Total seconds accumulated by [tick] since construction or [reset].
  double get elapsed => _elapsed;

  /// Advances the stopwatch by [delta] seconds.
  void tick(double delta) => _elapsed += delta;

  /// Sets the stopwatch back to zero.
  void reset() => _elapsed = 0;
}
