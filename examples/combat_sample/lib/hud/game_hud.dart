/// The flat HUD, routed on the run state: the fight overlay while
/// fighting, the skill menu while it is open, the death panel while lost,
/// the title screen before it starts. Each screen lives in its own file
/// under `hud/`; this is only the router (`GameStateBuilder` switches on
/// the [GameStatus]) plus the always-on FPS readout.
library;

import 'package:flutter/material.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';

import '../game/game_state.dart';
import 'death_panel.dart';
import 'fight_hud.dart';
import 'fps.dart';
import 'skill_menu.dart';
import 'title_menu.dart';

class GameHud extends StatelessWidget {
  const GameHud({super.key});

  @override
  Widget build(BuildContext context) {
    // The readout sits OUTSIDE the state switch: a frame rate you can
    // only see while fighting is no use for the two screens most likely
    // to be hiding a stall (the title orbit and the death slow-mo).
    return Stack(
      fit: StackFit.expand,
      children: [
        GameStateBuilder<GameStatus>(builder: _screenFor),
        const Align(
          alignment: Alignment.topRight,
          child: SafeArea(
            child: Padding(
              // Clear of the circular pause button (top-right, ~60px from
              // the edge) so the two never overlap while fighting.
              padding: EdgeInsets.only(top: 20, right: 70),
              child: FpsCounter(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _screenFor(BuildContext context, GameStatus status) =>
      switch (status) {
        GameStatus.fighting => const FightHud(),
        GameStatus.skillMenu => const SkillMenu(),
        GameStatus.lost => const DeathPanel(),
        GameStatus.title => const TitleMenu(),
      };
}
