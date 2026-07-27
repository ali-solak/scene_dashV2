import 'dart:async';

import 'package:flutter/foundation.dart' show Listenable;
import 'package:flutter/widgets.dart' show WidgetsFlutterBinding;
import 'package:flutter_scene/scene.dart' show Scene;
import 'package:flutter_scene/physics.dart' show PhysicsWorld;
import 'package:scene_dash_v2_core/advanced.dart';

import 'entity_collision.dart';
import 'game.dart';
import 'physics_plugin.dart';
import 'scene_commands.dart';
import 'node_ref.dart';
import 'scene_transform.dart';

/// A game without a scene.
class WorldGame {
  /// ECS engine.
  final Game engine;

  WorldGame._(this.engine);

  /// Starts a game without a scene.
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

  /// Installs shared game features.
  Future<void> _install({
    required PhysicsWorld? physics,
    required List<Feature> features,
    required bool strictAccess,
    required void Function(String message)? onDiagnostic,
  }) async {
    final world = engine.world;
    SpawnQueue.of(world).onDiagnostic = onDiagnostic;
    // Register scene component stores.
    world
      ..ensureObjectStore<NodeRef>()
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

  /// Pulses after each rendered frame.
  Listenable get frameTick => engine.frameTick;

  /// Sends [event] into the world.
  void emit<E extends Object>(E event) {
    if (E == event.runtimeType) world.registerEvent<E>();
    world.sendEvent(event);
  }

  /// Hot-reload hook, forwarded by `GameHost`.
  void reassemble() {}

  /// Advances the game loop.
  void onTick(Duration elapsed, double deltaSeconds) =>
      engine.onTick(elapsed, deltaSeconds);

  /// Shuts down the engine and detaches the scene driver.
  Future<void> shutdown() => engine.shutdown();
}

/// A game with a scene.
final class SceneGame extends WorldGame {
  /// Rendered scene.
  final Scene scene;

  SceneGame._(this.scene, Game engine) : super._(engine);

  /// Starts a game with a scene.
  ///
  /// Requires a Flutter GPU context.
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
    // Let features configure the scene.
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
