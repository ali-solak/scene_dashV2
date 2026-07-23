/// The frame-rate readout.
///
/// Counted off a [Ticker], not the world clock: `world.dt` is scaled by
/// hitstop and death slow-motion, which would misreport deliberate
/// freezes as low FPS. This counts frames actually presented.
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
  // Started in initState, NOT as a `late final` initialiser: a `late`
  // field is built on first read, and nothing reads the ticker before
  // `dispose`, so the lazy form never started it and the counter sat at 0.
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
    // Ash while healthy, amber once not; a colour reads faster than
    // digits do.
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
