import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart' show SceneView;
import 'package:scene_dash_v2/scene_dash_v2.dart';

import 'common/game_state.dart';
import 'features/arena/arena.dart';
import 'features/creeps/creeps.dart';
import 'features/rules/rules.dart';
import 'features/towers/towers.dart';
import 'hud/hud.dart';

Future<void> main() async {
  final game = await SceneGame.boot(
    features: [installArena, installCreeps, installTowers, installRules],
  );
  runApp(GameHost(game: game, child: TowerDefenseApp(game)));
}

class const TowerDefenseApp(final SceneGame game, {super.key})
    extends StatefulWidget {
  @override
  State<TowerDefenseApp> createState() => _TowerDefenseAppState();
}

class _TowerDefenseAppState extends State<TowerDefenseApp> {
  @override
  void dispose() {
    unawaited(widget.game.shutdown());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData.dark(),
    home: Scaffold(
      backgroundColor: const Color(0xFF05070B),
      body: Stack(
        fit: StackFit.expand,
        children: [
          _ArenaTaps(
            child: SceneView(widget.game.scene, onTick: widget.game.onTick),
          ),
          const Hud(),
        ],
      ),
    ),
  );
}

class const _ArenaTaps({required final Widget child}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTapDown: (details) => _place(context, details.localPosition),
    child: child,
  );

  void _place(BuildContext context, Offset at) {
    final viewSize = context.size;
    if (viewSize == null) return;
    final game = GameScope.of(context);
    game.emit(PlaceTowerRequested(at, viewSize));
  }
}
