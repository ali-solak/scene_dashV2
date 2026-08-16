/// A from-to interpolation over a duration, driven by an explicit `tick(dt)`.
library;

import 'package:flutter/animation.dart' show Curve;

/// Interpolates [from] to [to] over [duration], through an optional [curve].
///
/// A field on a component, ticked with `world.dt`, so it pauses and slows with
/// the game.
///
/// ```dart
/// final flash = GameTween.number(1, 0, 0.25, curve: Curves.easeOut);
/// flash.tick(world.dt);
/// material.baseColorFactor.a = flash.value;
/// ```
final class GameTween<T> {
  /// A tween over any type [lerp] can mix.
  ///
  /// [lerp] is called on every [value] read, so keep it cheap and free of
  /// state. Use [GameTween.number] for doubles and the `vector3Tween` /
  /// `colorTween` helpers for `vector_math` types.
  GameTween(
    T from,
    T to,
    double seconds, {
    required this.lerp,
    this.curve,
  }) : _from = from,
       _to = to,
       _duration = seconds,
       assert(
         seconds > 0,
         'GameTween needs a positive duration. A zero-duration tween is '
         'finished from birth but never reports justFinished, so any system '
         'waiting on that edge silently never runs. Set the value directly '
         'instead, or give the tween a duration.',
       );

  /// A tween between two numbers.
  static GameTween<double> number(
    double from,
    double to,
    double seconds, {
    Curve? curve,
  }) => GameTween<double>(from, to, seconds, lerp: _lerpDouble, curve: curve);

  static double _lerpDouble(double from, double to, double t) =>
      from + (to - from) * t;

  /// The curve applied to [fraction]. Null is linear. Swappable at runtime.
  Curve? curve;

  /// Mixes [from] and [to] by [eased]. Set once, at construction.
  final T Function(T from, T to, double t) lerp;

  T _from;
  T _to;
  double _duration;
  double _elapsed = 0;
  int _direction = 1;
  bool _justFinished = false;

  /// Where the tween starts. [retarget] moves it to the current [value].
  T get from => _from;

  /// Where the tween ends.
  T get to => _to;

  /// The span the tween covers, in seconds.
  double get duration => _duration;

  set duration(double seconds) {
    assert(seconds > 0, 'GameTween needs a positive duration.');
    _duration = seconds;
    if (_elapsed > seconds) _elapsed = seconds;
  }

  /// Seconds travelled, clamped to `[0, duration]`.
  double get elapsed => _elapsed;

  /// Raw linear progress in `[0, 1]`.
  ///
  /// The same quantity as `GameTimer.fraction`, and the input to [curve].
  double get fraction {
    if (_duration <= 0) return 1;
    final f = _elapsed / _duration;
    return f < 0 ? 0 : (f > 1 ? 1 : f);
  }

  /// [fraction] through [curve], or [fraction] itself when there is no curve.
  ///
  /// Deliberately not clamped to `[0, 1]`: `Curves.easeOutBack` overshoots
  /// past 1 near the end, and that overshoot is the effect. Clamping here
  /// would flatten every anticipation and settle curve in the catalogue.
  double get eased => curve?.transform(fraction) ?? fraction;

  /// [from] and [to] mixed by [eased].
  ///
  /// For a `GameTween<double>` this is free. For vector instantiations it
  /// builds a new value on every read; in a per-entity system, prefer the
  /// `valueInto` extension.
  T get value => lerp(_from, _to, eased);

  /// Whether the tween reached the end it was travelling toward.
  ///
  /// Latches until [reset], [retarget] or [reverse]. A finished tween costs
  /// nothing per frame: [tick] returns immediately.
  bool get finished =>
      _direction > 0 ? (_duration <= 0 || _elapsed >= _duration) : _elapsed <= 0;

  /// Whether the most recent [tick] reached the end. True for exactly one tick.
  bool get justFinished => _justFinished;

  /// Whether the tween is playing backwards. See [reverse].
  bool get reversed => _direction < 0;

  /// Advances by [delta] seconds, clearing [justFinished] first.
  ///
  /// Like the rest of the family, the edge is cleared at the start of the
  /// tick, so every system later in the frame sees it exactly once.
  void tick(double delta) {
    _justFinished = false;
    if (finished) return;
    _elapsed += delta * _direction;
    if (_direction > 0) {
      if (_elapsed >= _duration) {
        _elapsed = _duration;
        _justFinished = true;
      }
      return;
    }
    if (_elapsed <= 0) {
      _elapsed = 0;
      _justFinished = true;
    }
  }

  /// Restarts from [from], forwards, with the same endpoints and duration.
  void reset() {
    _elapsed = 0;
    _direction = 1;
    _justFinished = false;
  }

  /// Restarts toward [target] from wherever the tween currently sits.
  ///
  /// Reads [value] before rewinding, so redirecting mid-flight is continuous:
  /// a camera easing toward one target and relocked onto another bends instead
  /// of snapping. Works on a finished tween, which it un-finishes.
  ///
  /// [duration] is kept, so travel time is constant and speed scales with
  /// distance. That is right for cinematic easing and wrong for chasing; if
  /// the destination moves every frame, reach for `smoothTo` instead.
  void retarget(T target) {
    _from = value;
    _to = target;
    _elapsed = 0;
    _direction = 1;
    _justFinished = false;
  }

  /// Plays back the way it came, from wherever it is now.
  ///
  /// Time runs backwards rather than the endpoints swapping, so [value] is a
  /// pure function of [elapsed] and cannot step at the call: the tween
  /// retraces the exact path it drew, curve included. Two calls are an exact
  /// identity, and reversing before the first tick finishes immediately.
  ///
  /// Leaves [justFinished] alone, so reversing on the edge does not hide it
  /// from later systems. Pair the two for ping-pong, which is also how a pop
  /// is built, since a `sin(pi * t)` curve cannot be a `Curve`:
  ///
  /// ```dart
  /// platform.slide.tick(world.dt);
  /// if (platform.slide.justFinished) platform.slide.reverse();
  /// ```
  void reverse() => _direction = -_direction;

  /// Progress and time, e.g. `70% (0.35/0.50s)`.
  @override
  String toString() {
    final pct = (fraction * 100).round();
    final back = _direction < 0 ? ' reversed' : '';
    return '$pct%$back (${_elapsed.toStringAsFixed(2)}/'
        '${_duration.toStringAsFixed(2)}s)';
  }
}
