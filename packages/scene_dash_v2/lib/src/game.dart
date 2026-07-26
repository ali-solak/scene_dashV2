import 'package:flutter/foundation.dart'
    show Listenable, debugPrint, kDebugMode;
import 'package:flutter_scene/scene.dart' show Node, Scene;
import 'package:scene_dash_v2_core/advanced.dart';

import 'frame_tick.dart';
import 'scene_commands.dart';
import 'scene_driver.dart';
import 'scene_mount.dart';
import 'scene_node_index.dart';
import 'scene_sync.dart';
import 'scene_transform.dart';

/// Connects an [App] to a scene.
final class Game {
  /// The app-owned scene this game renders into, or `null` for a headless
  /// engine (see [Game.headless]).
  final Scene? scene;

  /// The node the driver attaches to and bound nodes mount under:
  /// `scene.root`, or a standalone node in headless mode.
  final Node root;

  /// The underlying scene-agnostic engine.
  final App app;

  /// Deferred scene-graph mutations, flushed once per frame (and after
  /// startup). Also injectable into systems as an `@Resource()`.
  late final SceneCommands sceneCommands = SceneCommands(root);

  /// Live node → entity index, exposed to systems as a [SceneNodeIndex] resource
  /// and maintained by the mount adapter.
  final Map<Node, Entity> _nodeIndex = <Node, Entity>{};

  /// Mounts entity nodes before updates.
  late final SceneNodeMountAdapter _mountAdapter = SceneNodeMountAdapter(
    sceneCommands,
    _nodeIndex,
  );

  late final EcsFrameLoop _loop = EcsFrameLoop(
    app,
    onCommandBoundary: _mountStep,
    onFrameEnd: _onFrameEnd,
  );

  /// Finishes scene work for one frame.
  void _onFrameEnd() {
    sceneCommands.flush();
    _extraFrameEnd?.call();
    _frameTick.pulse();
  }

  final FrameTickNotifier _frameTick = FrameTickNotifier();

  /// Pulses after each rendered frame.
  Listenable get frameTick => _frameTick;

  /// Mounts new nodes and flushes scene commands.
  void _mountStep() {
    _mountAdapter.run();
    sceneCommands.flush();
    _extraCommandBoundary?.call();
  }

  bool _started = false;
  bool _shutdown = false;
  EcsSceneDriver? _driver;

  /// Creates a scene game.
  Game({
    required Scene this.scene,
    AccessConflictPolicy accessConflictPolicy = AccessConflictPolicy.warn,
    void Function(String message)? onDiagnostic,
    AppDiagnostics diagnostics = const AppDiagnostics(),
    void Function()? onCommandBoundary,
    void Function()? onFrameEnd,
  }) : root = scene.root,
       _extraCommandBoundary = onCommandBoundary,
       _extraFrameEnd = onFrameEnd,
       app = App(
         accessConflictPolicy: accessConflictPolicy,
         onDiagnostic: onDiagnostic ?? _defaultDiagnosticSink,
         diagnostics: diagnostics,
       );

  /// Creates a game without a scene or GPU.
  Game.headless({
    AccessConflictPolicy accessConflictPolicy = AccessConflictPolicy.warn,
    void Function(String message)? onDiagnostic,
    AppDiagnostics diagnostics = const AppDiagnostics(),
    void Function()? onCommandBoundary,
    void Function()? onFrameEnd,
  }) : scene = null,
       root = Node(),
       _extraCommandBoundary = onCommandBoundary,
       _extraFrameEnd = onFrameEnd,
       app = App(
         accessConflictPolicy: accessConflictPolicy,
         onDiagnostic: onDiagnostic ?? _defaultDiagnosticSink,
         diagnostics: diagnostics,
       );

  /// Prints diagnostics in debug builds.
  static void Function(String message)? get _defaultDiagnosticSink =>
      kDebugMode ? _printDiagnostic : null;

  static void _printDiagnostic(String message) =>
      debugPrint('scene_dash_v2: $message');

  final void Function()? _extraCommandBoundary;
  final void Function()? _extraFrameEnd;

  /// The ECS world.
  World get world => app.world;

  /// The system profiler, or null when profiling is disabled (see
  /// `AppDiagnostics`).
  SystemProfiler? get profiler => app.profiler;

  /// Registers [plugin]. Mirrors [App.addPlugin] for fluent setup.
  Game addPlugin(Plugin plugin) {
    app.addPlugin(plugin);
    return this;
  }

  /// Sends [event] to its runtime type channel.
  void dispatch(Object event) => world.sendEvent(event);

  /// Registers a state machine for [S], starting at [initial]. Mirrors
  /// [AppBuilder.addState]; transitions apply at the frame-start boundary.
  Game addState<S extends Object>(S initial) {
    app.addState<S>(initial);
    return this;
  }

  /// Orders [sets] within [schedule].
  Game configureSets(ScheduleLabel schedule, List<SystemSet> sets) {
    app.configureSets(schedule, sets);
    return this;
  }

  /// Inserts [resource] before [start].
  Game insertResource<T extends Object>(T resource) {
    app.insertResource<T>(resource);
    return this;
  }

  /// Replaces (or inserts) a resource before [start]. Use when swapping is
  /// intentional.
  Game replaceResource<T extends Object>(T resource) {
    app.replaceResource<T>(resource);
    return this;
  }

  /// Finalizes the app and attaches the scene driver to the scene root.
  ///
  /// Call `await Scene.initializeStaticResources()` before rendering (as the
  /// `flutter_scene` examples do); it is not this method's responsibility.
  Future<void> start() async {
    if (_started) {
      throw StateError('Game has already been started.');
    }
    _loop.ensureTimeResources();
    // Insert scene resources.
    final scene = this.scene;
    if (scene != null) app.world.resources.insert<Scene>(scene);
    app.world.resources
      ..insert<SceneCommands>(sceneCommands)
      ..insert<SceneNodeIndex>(SceneNodeIndex(_nodeIndex));
    // Sync entity transforms to scene nodes.
    app.addSystemAdapter(
      SyncSceneNodesAdapter<SceneTransform>.full(
        (transform, target) => target.setFromTranslationRotationScale(
          transform.translation,
          transform.rotation,
          transform.scale,
        ),
      ),
      schedule: Schedules.renderSync,
      label: const SystemLabel('scene.syncTransform'),
    );
    // Flush startup spawns before state entry.
    app.start(onStartupFlushed: _extraCommandBoundary);
    // The mount adapter is not scheduled, so initialize it explicitly now that
    // stores exist, then mount any nodes spawned by startup systems and flush so
    // they are parented before the first frame's fixed/update steps run.
    _mountAdapter.initialize(app.world);
    _mountStep();
    final driver = EcsSceneDriver(_loop);
    root.addComponent(driver);
    _driver = driver;
    _started = true;
  }

  /// Advances ECS and scene time by one frame.
  void onTick(Duration elapsed, double deltaSeconds) {
    final scaledDelta = _loop.frameStart(elapsed, deltaSeconds);
    final scene = this.scene;
    if (scene != null) {
      scene.update(scaledDelta);
    } else {
      // Run the headless driver directly.
      _driver!.update(scaledDelta);
    }
  }

  /// Shuts down the underlying app and detaches the internal scene driver.
  Future<void> shutdown() async {
    if (!_started || _shutdown) return;
    _shutdown = true;
    await app.shutdown();
    final driver = _driver;
    if (driver != null) {
      root.removeComponent(driver);
      _driver = null;
    }
    sceneCommands.flush();
    _frameTick.dispose();
  }
}
