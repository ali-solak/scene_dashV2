import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:material_ui/material_ui.dart';

import '../common/actors.dart' show HitWeight;
import 'ink.dart';

class DamageNumberWidget extends StatelessWidget {
  const DamageNumberWidget({
    super.key,
    required this.amount,
    required this.weight,
    required this.hurt,
    required this.ticking,
    required this.opacity,
  });

  final double amount;
  final HitWeight weight;
  final bool hurt;
  final bool ticking;
  final ValueListenable<double> opacity;

  Color get _fill {
    if (hurt) return const Color(0xFFE0483C);
    if (ticking) return const Color(0xFFE0A050);
    return switch (weight) {
      HitWeight.light => HudInk.bone,
      HitWeight.finisher => const Color(0xFFFFD27A),
      HitWeight.heavy => const Color(0xFFFF9A45),
    };
  }

  double get _size => switch (weight) {
    _ when ticking => 40,
    HitWeight.light => 56,
    HitWeight.finisher => 76,
    HitWeight.heavy => 68,
  };

  @override
  Widget build(BuildContext context) {
    final label = amount.round().toString();
    final style = TextStyle(
      fontSize: _size,
      fontWeight: FontWeight.w900,
      letterSpacing: 1,
      height: 1,
    );
    return ValueListenableBuilder<double>(
      valueListenable: opacity,
      builder: (context, value, _) => Opacity(
        opacity: value.clamp(0.0, 1.0),
        child: Center(
          child: Stack(
            children: [
              Text(
                label,
                style: style.copyWith(
                  foreground: Paint()
                    ..style = PaintingStyle.stroke
                    ..strokeWidth = 8
                    ..color = const Color(0xFF0B0C0D),
                ),
              ),
              Text(label, style: style.copyWith(color: _fill)),
            ],
          ),
        ),
      ),
    );
  }
}
