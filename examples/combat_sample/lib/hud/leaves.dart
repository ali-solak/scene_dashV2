/// Ambient leaves drifting across the pause screen on their own ticker,
/// so the frozen menu still feels like it sits in the clearing. Cheap:
/// one full-screen [CustomPaint], a dozen-odd path fills. The host wraps
/// it in an [IgnorePointer] so it never eats a tap.
library;

import 'dart:math' as math;

import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter/widgets.dart';

class Leaves extends StatefulWidget {
  const Leaves({super.key, this.count = 18});

  /// How many leaves are aloft at once. Kept low; this drifts over a menu,
  /// it is not a storm.
  final int count;

  @override
  State<Leaves> createState() => _LeavesState();
}

class _LeavesState extends State<Leaves> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;

  // The clock the painter reads. A ValueNotifier (not setState) so only the
  // CustomPaint repaints, never the widget tree.
  final ValueNotifier<double> _time = ValueNotifier<double>(0);
  late final List<_Leaf> _leaves;

  @override
  void initState() {
    super.initState();
    // Seeded, so the drift is the same every time the menu opens rather than
    // re-scattering on each pause.
    final rng = math.Random(7);
    _leaves = List.generate(widget.count, (_) => _Leaf.random(rng));
    _ticker = createTicker((elapsed) {
      _time.value = elapsed.inMicroseconds / 1e6;
    })..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.infinite,
      painter: _LeafPainter(_time, _leaves),
    );
  }
}

/// One leaf's fixed character; the painter turns time into its position.
class _Leaf {
  const _Leaf({
    required this.baseX,
    required this.drift,
    required this.fall,
    required this.phase,
    required this.size,
    required this.sway,
    required this.swayFreq,
    required this.spin,
    required this.color,
  });

  /// Column it falls down (fraction of width), the sideways wind carrying it
  /// across as it drops, and how long top-to-bottom takes (seconds).
  final double baseX;
  final double drift;
  final double fall;

  /// 0..1 offset into its loop, so they do not all fall in step.
  final double phase;

  /// Half-length in px, the sway amplitude and frequency, and its spin.
  final double size;
  final double sway;
  final double swayFreq;
  final double spin;

  final Color color;

  factory _Leaf.random(math.Random r) {
    const palette = [
      Color(0xFF8FB05A), // leaf green
      Color(0xFFB9C56A), // pale green
      Color(0xFFE0A93B), // amber
      Color(0xFFD98A3A), // orange
      Color(0xFFC5693A), // rust
    ];
    return _Leaf(
      baseX: r.nextDouble() * 1.1 - 0.05,
      drift: 0.10 + r.nextDouble() * 0.24,
      fall: 7 + r.nextDouble() * 9,
      phase: r.nextDouble(),
      size: 7 + r.nextDouble() * 9,
      sway: 14 + r.nextDouble() * 34,
      swayFreq: 0.5 + r.nextDouble() * 1.1,
      spin: (r.nextDouble() * 2 - 1) * 0.9,
      color: palette[r.nextInt(palette.length)],
    );
  }
}

class _LeafPainter extends CustomPainter {
  _LeafPainter(this.time, this.leaves) : super(repaint: time);

  final ValueNotifier<double> time;
  final List<_Leaf> leaves;

  @override
  void paint(Canvas canvas, Size size) {
    final t = time.value;
    final w = size.width;
    final h = size.height;
    // Enough overhang that a leaf resets while fully off-screen, so the
    // top→bottom loop never visibly jumps.
    const margin = 48.0;
    for (final leaf in leaves) {
      final prog = ((t / leaf.fall) + leaf.phase) % 1.0;
      final y = prog * (h + 2 * margin) - margin;
      final x =
          (leaf.baseX + prog * leaf.drift) * w +
          leaf.sway * math.sin(t * leaf.swayFreq + leaf.phase * math.pi * 2);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(t * leaf.spin + leaf.phase * math.pi * 2);
      _paintLeaf(canvas, leaf);
      canvas.restore();
    }
  }

  void _paintLeaf(Canvas canvas, _Leaf leaf) {
    final s = leaf.size;
    final path = Path()
      ..moveTo(0, -s)
      ..quadraticBezierTo(s * 0.62, 0, 0, s)
      ..quadraticBezierTo(-s * 0.62, 0, 0, -s)
      ..close();
    canvas.drawPath(path, Paint()..color = leaf.color.withValues(alpha: 0.6));
    // A faint midrib, so up close it reads as a leaf and not a blob.
    canvas.drawLine(
      Offset(0, -s),
      Offset(0, s),
      Paint()
        ..color = const Color(0xFF5C5033).withValues(alpha: 0.26)
        ..strokeWidth = math.max(0.8, s * 0.06),
    );
  }

  @override
  bool shouldRepaint(_LeafPainter oldDelegate) => false; // repaints off `time`
}
