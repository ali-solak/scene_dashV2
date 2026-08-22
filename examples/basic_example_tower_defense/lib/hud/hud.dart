library;

import 'package:flutter/material.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';

import '../common/game_state.dart';
import '../features/creeps/creeps.dart';
import '../features/rules/rules.dart';
import '../features/towers/data/config.dart';

part 'stats.dart';
part 'lost_overlay.dart';

class Hud extends StatelessWidget {
  const Hud({super.key});

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      const SafeArea(
        child: IgnorePointer(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [_StatBar(), _Hint()],
            ),
          ),
        ),
      ),
      GameStateBuilder<GameStatus>(
        builder: (context, status) => switch (status) {
          GameStatus.playing => const SizedBox(),
          GameStatus.lost => const _LostOverlay(),
        },
      ),
    ],
  );
}
