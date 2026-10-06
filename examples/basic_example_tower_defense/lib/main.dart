import 'dart:async';

import 'package:flutter/gestures.dart' show kPrimaryButton;
import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart' show SceneView;
import 'package:scene_dash_v2/scene_dash_v2.dart';

import 'common/game_state.dart';
import 'features/arena/arena.dart';
import 'features/creeps/creeps.dart';
import 'features/damage/damage.dart';
import 'features/rules/rules.dart';
import 'features/towers/towers.dart';
import 'features/waves/waves.dart';
import 'hud/hud.dart';

Future<void> main() async {
  final game = await SceneGame.boot(
    features: [
      installArena,
      installDamage,
      installCreeps,
      installWaves,
      installTowers,
      installRules,
    ],
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
          _BoardInput(
            child: SceneView(widget.game.scene, onTick: widget.game.onTick),
          ),
          const Hud(),
        ],
      ),
    ),
  );
}

class const _BoardInput({required final Widget child}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => MouseRegion(
    onHover: (event) => _hover(context, event.localPosition),
    onExit: (_) => _hover(context, null),
    child: Listener(
      onPointerDown: (event) {
        if (event.buttons == kPrimaryButton) {
          _place(context, event.localPosition);
        }
      },
      child: child,
    ),
  );

  void _hover(BuildContext context, Offset? at) {
    final pointer = context.world.resource<BoardPointer>()..position = at;
    final viewSize = context.size;
    if (viewSize != null) pointer.viewSize = viewSize;
  }

  void _place(BuildContext context, Offset at) {
    final viewSize = context.size;
    if (viewSize == null) return;
    final game = GameScope.of(context);
    game.emit(PlaceTowerRequested(at, viewSize));
  }
}
