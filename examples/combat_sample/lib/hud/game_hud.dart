import 'package:material_ui/material_ui.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';

import '../common/game_state.dart';
import 'death_panel.dart';
import 'fight_hud.dart';
import 'fps.dart';
import 'skill_menu.dart';
import 'title_menu.dart';

class GameHud extends StatelessWidget {
  const GameHud({super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        GameStateBuilder<GameStatus>(builder: _screenFor),
        const Align(
          alignment: Alignment.topRight,
          child: SafeArea(
            child: Padding(
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
