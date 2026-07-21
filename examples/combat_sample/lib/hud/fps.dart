/// The frame-rate readout.
///
/// Counted off a [Ticker] rather than off the world clock on purpose:
/// `world.dt` is scaled by hitstop and by the death slow-motion, so a
/// gameplay-derived figure would read ~20 FPS every time the game froze
/// deliberately for weight — exactly backwards for a performance number.
/// This counts frames the engine actually presented.
library;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;

import 'ink.dart';

class FpsCounter extends StatefulWidget {
  const FpsCounter({
    super.key,
    this.window = const Duration(milliseconds: 500),
  });

  /// The rolling sample window. Long enough that the number is readable
  /// rather than flickering, short enough that a stall shows up while it
  /// is still happening.
  final Duration window;

  @override
  State<FpsCounter> createState() => _FpsCounterState();
}

class _FpsCounterState extends State<FpsCounter>
    with SingleTickerProviderStateMixin {
  // Started in initState, NOT as a `late final` initialiser.
  //
  // A `late` field is built on first READ, and nothing here ever reads
  // the ticker except `dispose` — so the lazy form never constructed it,
  // never started it, never ticked, and the counter sat at 0 forever.
  // (The skill slots' controller gets away with the lazy form only
  // because their build method reads it every frame.)
  late final Ticker _ticker;
  Duration _windowStart = Duration.zero;
  int _frames = 0;
  int _fps = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    _frames++;
    final span = elapsed - _windowStart;
    if (span < widget.window) return;
    final fps = (_frames * 1e6 / span.inMicroseconds).round();
    _windowStart = elapsed;
    _frames = 0;
    // Only when the displayed number actually changes: a setState every
    // window would rebuild for an identical string twice a second.
    if (fps != _fps && mounted) setState(() => _fps = fps);
  }

  @override
  Widget build(BuildContext context) {
    // Ash while it is holding up, amber once it is not — the number is
    // for glancing at, and a colour reads faster than digits do.
    final healthy = _fps >= 50;
    return Text(
      '$_fps FPS',
      style: TextStyle(
        color: healthy ? HudInk.ash : const Color(0xFFE07A2B),
        fontSize: 11,
        letterSpacing: 2,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}
