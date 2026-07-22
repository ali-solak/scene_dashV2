import 'dart:async';

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
/// (editor panels, previews).
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

/// Boots a game, holds the loading and error frames while it boots, and
/// hosts it once it is up — the widget every app otherwise hand-rolls
/// around [SceneGame.boot].
///
/// [boot] runs once (never re-run on rebuild), the result is wrapped in a
/// [GameHost] so the subtree gets a [GameScope] and the hot-reload hook,
/// and the game is `shutdown()` on dispose. A boot that finishes after the
/// widget is gone is shut down too, so a fast dispose never leaks a game.
///
/// Only lifecycle is owned here: [loading], [error] and [builder] are your
/// widgets, so the look stays yours (the framework still never builds your
/// `SceneView`).
///
/// ```dart
/// GameBootstrap<SceneGame>(
///   boot: () => SceneGame.boot(features: [...]),
///   loading: (context) => const SplashScreen(),
///   builder: (context, game) => GameShell(game: game),
/// )
/// ```
class GameBootstrap<G extends WorldGame> extends StatefulWidget {
  const GameBootstrap({
    super.key,
    required this.boot,
    required this.builder,
    this.loading,
    this.error,
  });

  /// Boots the game. Called once, in `initState`; the returned game is
  /// owned by this widget from then on (hosted, then shut down).
  final Future<G> Function() boot;

  /// Builds the tree for the running game. Wrapped in a [GameHost], so
  /// everything it builds can resolve the game from context.
  final Widget Function(BuildContext context, G game) builder;

  /// Held while [boot] runs. Defaults to a black hold.
  final WidgetBuilder? loading;

  /// Shown when [boot] throws. Defaults to Flutter's [ErrorWidget], so a
  /// boot failure is surfaced rather than swallowed behind the loader.
  final Widget Function(BuildContext context, Object error)? error;

  @override
  State<GameBootstrap<G>> createState() => _GameBootstrapState<G>();
}

class _GameBootstrapState<G extends WorldGame> extends State<GameBootstrap<G>> {
  G? _game;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    try {
      final game = await widget.boot();
      if (mounted) {
        setState(() => _game = game);
      } else {
        // Disposed mid-boot: nothing will ever call dispose for this game,
        // so shut it down here instead of leaking it.
        await game.shutdown();
      }
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  @override
  void dispose() {
    unawaited(_game?.shutdown());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    if (error != null) {
      return widget.error?.call(context, error) ?? ErrorWidget(error);
    }
    final game = _game;
    if (game == null) {
      return widget.loading?.call(context) ??
          const ColoredBox(color: Color(0xFF000000));
    }
    return GameHost(game: game, child: widget.builder(context, game));
  }
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
