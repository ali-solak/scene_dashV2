/// The in-world barbarian health bar — a `WidgetComponent` surface driven
/// by a `ValueListenable<double>` the health system pushes each frame
/// (the reticle's model-push idiom; no reactive `EntityBuilder` inside, so
/// no `GameScope` re-provision needed). Kept opaque-cored so the 0.19
/// premultiplied-alpha widget-capture quirk doesn't darken it.
library;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

class HealthBarWidget extends StatelessWidget {
  const HealthBarWidget({super.key, required this.fraction});

  final ValueListenable<double> fraction;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: fraction,
      builder: (context, value, _) {
        return Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: const Color(0xFF101014),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF000000), width: 3),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: Row(
              children: [
                Expanded(
                  flex: (value.clamp(0.0, 1.0) * 1000).round(),
                  child: Container(height: 22, color: const Color(0xFFE0483C)),
                ),
                Expanded(
                  flex: 1000 - (value.clamp(0.0, 1.0) * 1000).round(),
                  child: Container(height: 22, color: const Color(0xFF3A1414)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
