import 'package:flutter/widgets.dart';
import 'package:scene_dash_v2_core/scene_dash_v2_core.dart';

import 'scene_game.dart';

/// Exposes the running game to a widget subtree — the game, once,
/// at the root; every framework primitive below resolves it from context,
/// and `context.game`/`context.world` cover ad-hoc reads. Nearest-ancestor
/// wins, so multi-game layouts (split-screen, previews) work for free.
///
/// The framework never constructs or wraps `SceneView`: your layout, your
/// focus, your camera — this widget only provides discovery.
final class GameScope extends InheritedWidget {
  /// The game this subtree belongs to — a [SceneGame], or a [WorldGame]
  /// hosting widgets over a scene-less world.
  final WorldGame game;

  const GameScope({super.key, required this.game, required super.child});

  /// The nearest enclosing game. Throws outside a scope.
  static WorldGame of(BuildContext context) {
    final game = maybeOf(context);
    if (game == null) {
      throw FlutterError(
        'GameScope.of() called outside a GameScope. Wrap the tree in a '
        'GameScope (or GameHost) to provide the game.',
      );
    }
    return game;
  }

  /// The nearest enclosing game, or `null` when there is none.
  static WorldGame? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GameScope>()?.game;

  @override
  bool updateShouldNotify(GameScope oldWidget) => game != oldWidget.game;
}

/// [GameScope] plus the hot-reload hook: forwards [State.reassemble] to
/// the game. Zero visual opinion; headless games are legitimate children
/// (editor panels, previews). The app owns boot and shutdown; this widget
/// only hosts an already-running game.
class GameHost extends StatefulWidget {
  const GameHost({super.key, required this.game, required this.child});

  /// The booted game exposed to [child]'s subtree.
  final WorldGame game;

  /// Your widget tree — typically containing your own `SceneView`.
  final Widget child;

  @override
  State<GameHost> createState() => _GameHostState();
}

class _GameHostState extends State<GameHost> {
  @override
  void reassemble() {
    super.reassemble();
    widget.game.reassemble();
  }

  @override
  Widget build(BuildContext context) =>
      GameScope(game: widget.game, child: widget.child);
}

/// Ad-hoc world reads from any build method below a [GameScope]:
///
/// ```dart
/// Text('score: ${context.world.resource<Score>().value}')
/// ```
extension GameBuildContext on BuildContext {
  /// The nearest enclosing game.
  WorldGame get game => GameScope.of(this);

  /// The nearest enclosing game's world.
  World get world => game.world;
}
