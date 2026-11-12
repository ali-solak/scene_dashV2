library;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';

import '../common/game_state.dart';
import '../hud/game_hud.dart';

final Map<LogicalKeyboardKey, GameAction> gameKeys = {
  LogicalKeyboardKey.keyA: GameAction.left,
  LogicalKeyboardKey.arrowLeft: GameAction.left,
  LogicalKeyboardKey.keyD: GameAction.right,
  LogicalKeyboardKey.arrowRight: GameAction.right,
  LogicalKeyboardKey.space: GameAction.fire,
};

class GameControls extends StatelessWidget {
  const GameControls({super.key, required this.scene});

  final Widget scene;

  @override
  Widget build(BuildContext context) {
    void restart() => context.game.emit(const RestartRequested());
    return Focus(
      canRequestFocus: false,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent ||
            event.logicalKey != LogicalKeyboardKey.keyR) {
          return KeyEventResult.ignored;
        }
        restart();
        return KeyEventResult.handled;
      },
      child: InputBindings<GameAction>(
        keys: gameKeys,
        child: Stack(
          fit: StackFit.expand,
          children: [
            scene,
            GameHud(onRestart: restart),
          ],
        ),
      ),
    );
  }
}
