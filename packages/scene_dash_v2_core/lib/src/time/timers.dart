/// Frame-tick timing value types, modeled on Bevy's `Timer`/`Stopwatch`.
///
/// Both are plain mutable values driven by an explicit `tick(dt)` — normally
/// `FrameTime.delta` or `FixedTime.delta` — so they follow the `GameClock`
/// automatically (a paused game sends `delta == 0` and nothing advances).
/// They allocate nothing after construction, so they can live inside
/// components ticked every frame. (Named `GameTimer`/`GameStopwatch` rather
/// than Bevy's `Timer`/`Stopwatch` to avoid colliding with `dart:async` and
/// `dart:core`.)
library;

/// Counts up to a duration, reporting completion; one-shot or repeating.
///
/// One-shot (`repeating: false`): [finished] latches `true` once [elapsed]
/// reaches [duration] and stays there until [reset]. The cooldown idiom:
///
/// ```dart
/// if (firePressed && cooldown.finished) {
///   fire();
///   cooldown.reset();
/// }
/// cooldown.tick(time.delta);
/// ```
///
/// Repeating: on completion the overshoot rolls into the next period, so the
/// average rate is exact regardless of frame timing. A tick that crosses
/// several periods (a frame hitch over a fast spawner) reports every
/// completion through [completionsThisTick]:
///
/// ```dart
/// spawnTimer.tick(time.delta);
/// for (var i = 0; i < spawnTimer.completionsThisTick; i++) {
///   spawnRock(commands);
/// }
/// ```
final class GameTimer {
  /// The target duration, in seconds. Mutable; shortening it below [elapsed]
  /// makes a one-shot timer finish on the next [tick].
  double duration;

  /// Whether the timer restarts itself on completion.
  final bool repeating;

  double _elapsed = 0;
  bool _justFinished = false;
  int _completionsThisTick = 0;

  /// A one-shot timer: counts to [duration] once, then holds [finished].
  GameTimer(this.duration) : repeating = false;

  /// A repeating timer: completes every [duration] seconds. [duration] must
  /// be positive.
  GameTimer.repeating(this.duration)
    : repeating = true,
      assert(duration > 0, 'A repeating GameTimer needs a positive duration.');

  /// Seconds accumulated toward the current period.
  double get elapsed => _elapsed;

  /// Whether the timer has completed. One-shot timers latch `true`; a
  /// repeating timer is only "finished" on the tick it completes (it
  /// immediately starts the next period), so this equals [justFinished].
  bool get finished =>
      repeating ? _justFinished : duration <= 0 || _elapsed >= duration;

  /// Whether the most recent [tick] completed the timer.
  bool get justFinished => _justFinished;

  /// How many periods the most recent [tick] completed: `0` most ticks, `1`
  /// on completion, more when one tick of a repeating timer spans several
  /// periods.
  int get completionsThisTick => _completionsThisTick;

  /// Progress through the current period in `[0, 1]`. A finished one-shot
  /// (or non-positive [duration]) reports `1`.
  double get fraction {
    if (duration <= 0) return 1;
    final f = _elapsed / duration;
    return f < 0 ? 0 : (f > 1 ? 1 : f);
  }

  /// Seconds left in the current period (`0` when finished).
  double get remaining {
    final r = duration - _elapsed;
    return r < 0 ? 0 : r;
  }

  /// Advances the timer by [delta] seconds and updates [justFinished] /
  /// [completionsThisTick] for this tick. A finished one-shot stays finished
  /// but no longer reports [justFinished].
  void tick(double delta) {
    _justFinished = false;
    _completionsThisTick = 0;
    if (!repeating) {
      if (_elapsed >= duration) return; // Already finished; nothing to cross.
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
      // Constant-time wrap: a huge delta over a tiny period must not loop.
      final periods = _elapsed ~/ duration;
      _elapsed -= periods * duration;
      _completionsThisTick = periods;
      _justFinished = true;
    }
  }

  /// Restarts the timer from zero, clearing completion state. Pass
  /// [duration] to change the target at the same time (a variable-length
  /// attack phase reusing one timer).
  void reset([double? duration]) {
    if (duration != null) this.duration = duration;
    _elapsed = 0;
    _justFinished = false;
    _completionsThisTick = 0;
  }
}

/// Counts up without a target: time-in-state, combo windows, run time.
final class GameStopwatch {
  double _elapsed = 0;

  /// Total seconds accumulated by [tick] since construction or [reset].
  double get elapsed => _elapsed;

  /// Advances the stopwatch by [delta] seconds.
  void tick(double delta) => _elapsed += delta;

  /// Sets the stopwatch back to zero.
  void reset() => _elapsed = 0;
}
