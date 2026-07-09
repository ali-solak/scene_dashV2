import 'dart:async';

import 'package:flutter/foundation.dart' show Listenable;
import 'package:flutter/widgets.dart' show WidgetsFlutterBinding;
import 'package:flutter_scene/scene.dart' show PhysicsWorld, Scene;
import 'package:scene_dash_v2_core/advanced.dart';

import 'entity_collision.dart';
import 'game.dart';
import 'physics_plugin.dart';
import 'scene_commands.dart';
import 'scene_node.dart';
import 'scene_transform.dart';

/// A booted world a widget tree can host: the ECS world, the gameplay
/// clock, the frame heartbeat, and the loop — everything the §1.9 widget
/// primitives bind to, and nothing visual.
///
/// Modes are types (D13), never a nullable field: a rendering game is
/// [SceneGame], which always owns its [SceneGame.scene]; a widget tree
/// over a scene-less world — editor panels, widget-test harnesses, where
/// a real `Scene` would demand a GPU context — boots a [WorldGame]
/// directly. Pure-logic suites with no widget tree at all want the core
/// package's `TestGame` instead.
class WorldGame {
  /// The internal engine — interop tier, for migration code that still
  /// registers classic plugins or systems.
  final Game engine;

  WorldGame._(this.engine);

  /// Boots a scene-less game: wires physics (the collision bridge and
  /// entity resolution) when [physics] is given, runs [features] against
  /// a [GameBuilder] in order, then starts the engine.
  ///
  /// [strictAccess] makes systems registered without `reads:`/`writes:` a
  /// boot error (§1.8); the conflict-detector policy stays configurable
  /// separately.
  static Future<WorldGame> boot({
    PhysicsWorld? physics,
    List<Feature> features = const <Feature>[],
    bool strictAccess = false,
    AppDiagnostics diagnostics = const AppDiagnostics(),
    void Function(String message)? onDiagnostic,
    AccessConflictPolicy accessConflictPolicy = AccessConflictPolicy.warn,
  }) async {
    late final World world;
    final engine = Game.headless(
      accessConflictPolicy: accessConflictPolicy,
      onDiagnostic: onDiagnostic,
      diagnostics: diagnostics,
      onCommandBoundary: () => SpawnQueue.of(world).flush(),
    );
    world = engine.world;
    final game = WorldGame._(engine);
    await game._install(
      physics: physics,
      features: features,
      strictAccess: strictAccess,
      onDiagnostic: onDiagnostic,
    );
    return game;
  }

  /// The shared back half of both boots: store pre-registration, physics
  /// wiring, feature installation, and engine start.
  Future<void> _install({
    required PhysicsWorld? physics,
    required List<Feature> features,
    required bool strictAccess,
    required void Function(String message)? onDiagnostic,
  }) async {
    final world = engine.world;
    SpawnQueue.of(world).onDiagnostic = onDiagnostic;
    // Pre-register the integration component stores so spawn-list parts
    // (SceneNode, SceneTransform, the marker tags) insert directly instead
    // of parking — markers have no typed use to claim them.
    world
      ..ensureObjectStore<SceneNode>()
      ..ensureObjectStore<SceneTransform>()
      ..ensureTagStore<PhysicsDriven>()
      ..ensureTagStore<Mounted>();
    if (physics != null) {
      engine.root.addComponent(physics);
      engine
        ..addPlugin(PhysicsPlugin(physics))
        ..addPlugin(const EntityCollisionPlugin());
    }
    final builder = GameBuilder(engine.app, strictAccess: strictAccess);
    for (final feature in features) {
      feature(builder);
    }
    SpawnQueue.of(world).flush();
    await engine.start();
  }

  /// The ECS world.
  World get world => engine.world;

  /// The gameplay clock (pause, `timeScale`, `freezeFor` hitstop).
  GameClock get clock => world.resources.get<GameClock>();

  /// The presentation heartbeat: pulses once at the end of every rendered
  /// frame, after the world is fully resolved. The §1.9 widget primitives
  /// build on it.
  Listenable get frameTick => engine.frameTick;

  /// Sends [event] into the world — the widget-to-gameplay path. The
  /// channel registers on first use.
  void emit<E extends Object>(E event) {
    if (E == event.runtimeType) world.registerEvent<E>();
    world.sendEvent(event);
  }

  /// Hot-reload hook, forwarded by `GameHost`.
  void reassemble() {}

  /// The frame-tick handler — you drive the loop from your own widget
  /// (a `SceneView` for a [SceneGame]; any ticker for a [WorldGame]).
  void onTick(Duration elapsed, double deltaSeconds) =>
      engine.onTick(elapsed, deltaSeconds);

  /// Shuts down the engine and detaches the scene driver.
  Future<void> shutdown() => engine.shutdown();
}

/// The booted rendering game: the engine, the scene, and the loop handle —
/// nothing visual. The widget tree stays yours; `SceneView` is
/// flutter_scene's widget and the framework never constructs it:
///
/// ```dart
/// void main() async {
///   final game = await SceneGame.boot(
///     physics: RapierWorld(gravity: gravity),
///     features: [installWorldGeometry, installPlayer, installRules],
///   );
///   runApp(GameScope(
///     game: game,
///     child: MyApp(),   // your SceneView(game.scene, onTick: game.onTick)
///   ));
/// }
/// ```
final class SceneGame extends WorldGame {
  /// The scene this game renders into. Always present — a [SceneGame]
  /// owns a scene by definition (D13); scene-less hosting is [WorldGame].
  final Scene scene;

  SceneGame._(this.scene, Game engine) : super._(engine);

  /// Boots a rendering game: initializes `flutter_scene`'s static
  /// resources, builds the [scene] (or adopts the one you pass), wires
  /// physics when [physics] is given, runs [features] against a
  /// [GameBuilder] in order, then starts the engine.
  ///
  /// A real `Scene` needs a Flutter GPU context, so this boot fails fast
  /// without one — widget tests over a headless world boot [WorldGame],
  /// pure-logic suites boot the core `TestGame`.
  static Future<SceneGame> boot({
    Scene? scene,
    PhysicsWorld? physics,
    List<Feature> features = const <Feature>[],
    bool strictAccess = false,
    AppDiagnostics diagnostics = const AppDiagnostics(),
    void Function(String message)? onDiagnostic,
    AccessConflictPolicy accessConflictPolicy = AccessConflictPolicy.warn,
  }) async {
    WidgetsFlutterBinding.ensureInitialized();
    await Scene.initializeStaticResources();
    final resolvedScene = scene ?? Scene();
    late final World world;
    final engine = Game(
      scene: resolvedScene,
      accessConflictPolicy: accessConflictPolicy,
      onDiagnostic: onDiagnostic,
      diagnostics: diagnostics,
      onCommandBoundary: () => SpawnQueue.of(world).flush(),
    );
    world = engine.world;
    final game = SceneGame._(resolvedScene, engine);
    // Early, so features can configure the scene; Game.start re-inserts
    // the same instance harmlessly.
    world.resources.insert<Scene>(resolvedScene);
    await game._install(
      physics: physics,
      features: features,
      strictAccess: strictAccess,
      onDiagnostic: onDiagnostic,
    );
    return game;
  }

  /// Deferred scene-graph mutations, flushed once per frame.
  SceneCommands get sceneCommands => engine.sceneCommands;
}
