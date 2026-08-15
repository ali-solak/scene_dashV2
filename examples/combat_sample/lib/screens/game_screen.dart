/// Displays a running game.
library;

import 'package:material_ui/material_ui.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';

import '../hud/game_hud.dart';
import 'controls.dart';

class GameScreen extends StatelessWidget {
  const GameScreen({super.key, required this.game, required this.scene});

  final SceneGame game;

  /// The app's `SceneView`, carrying a `GlobalKey` so this reparent keeps
  /// its element and its warm-up state.
  final Widget scene;

  @override
  Widget build(BuildContext context) {
    return GameHost(
      game: game,
      child: GameControls(
        showTouchControls: showTouchControls,
        scene: scene,
        hud: const GameHud(),
      ),
    );
  }
}
