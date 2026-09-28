import 'package:material_ui/material_ui.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';

import '../features/feedback/feedback.dart' show ComboMeter;
import 'ink.dart';

const int _comboShownFrom = 2;

class ComboCounter extends StatelessWidget {
  const ComboCounter({super.key});

  @override
  Widget build(BuildContext context) {
    return WorldBuilder<int>(
      select: _comboHits,
      builder: (context, hits) => AnimatedOpacity(
        opacity: hits >= _comboShownFrom ? 1 : 0,
        duration: const Duration(milliseconds: 220),
        child: _ComboPop(hits: hits),
      ),
    );
  }
}

class _ComboPop extends StatelessWidget {
  const _ComboPop({required this.hits});

  final int hits;

  @override
  Widget build(BuildContext context) {
    return WorldBuilder<int>.pulse(
      select: _comboHits,
      trigger: (previous, next) => next > previous,
      duration: 0.28,
      pulseBuilder: (context, pulse, _) => Transform.scale(
        scale: 1 + 0.45 * pulse * pulse,
        alignment: Alignment.centerRight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$hits',
              style: TextStyle(
                color: Color.lerp(HudInk.bone, const Color(0xFFFFD27A), pulse),
                fontSize: 54,
                fontWeight: FontWeight.w900,
                height: 1,
                shadows: const [
                  Shadow(color: Color(0xCC000000), blurRadius: 8),
                ],
              ),
            ),
            const Text(
              'HITS',
              style: TextStyle(
                color: HudInk.ash,
                fontSize: 13,
                letterSpacing: 4,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

int _comboHits(World world) => world.resource<ComboMeter>().hits;
