import 'package:flutter/foundation.dart' show Listenable;
import 'package:flutter_scene/scene.dart' show Node, Scene;
import 'package:scene_dash_v2_core/advanced.dart';


import 'frame_tick.dart';
import 'scene_commands.dart';
import 'scene_driver.dart';
import 'scene_mount.dart';
import 'scene_node_index.dart';
import 'scene_sync.dart';
import 'scene_transform.dart';

/// The scene-aware facade over the core [App].
///
/// `Game` composes an [App] with a `flutter_scene` [Scene] and installs the
/// standard scene integration automatically, so feature plugins register only
/// their own systems. On [start] it:
///
/// * exposes the real [Scene] and [SceneCommands] as `@Resource()`s;
/// * auto-mounts entity-bound nodes ([SceneNode]) into the scene;
/// * synchronizes the standard [SceneTransform] onto bound nodes each frame;
/// * attaches the internal [EcsSceneDriver] and exposes [onTick] for `SceneView`;
/// * drives the scene tick on [GameClock]-scaled time, so `timeScale`,
///   `paused`, and `freezeFor` (hitstop) apply to physics, animations, and
///   gameplay together.
///
/// (Use `CustomSceneSyncPlugin<T>` only for a non-standard transform type.)
///
/// ```dart
/// await Scene.initializeStaticResources();
/// final scene = Scene();
/// final game = Game(scene: scene)
///   ..addPlugin(const InputPlugin())
///   ..addPlugin(const PlayerPlugin());
/// await game.start();
///
/// return SceneView(scene, cameraBuilder: buildCamera, onTick: game.onTick);
/// ```
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

  /// Mounts entity-bound nodes into the scene. Owned by `Game` (not registered
  /// in a schedule) so it can run *before* the `update` phase — see [_mountStep].
  late final SceneNodeMountAdapter _mountAdapter = SceneNodeMountAdapter(
    sceneCommands,
    _nodeIndex,
  );

  late final EcsFrameLoop _loop = EcsFrameLoop(
    app,
    onCommandBoundary: _mountStep,
    onFrameEnd: _onFrameEnd,
  );

  /// Frame-end work: flush deferred scene-graph mutations, run the caller's
  /// frame-end hook (if any), then pulse the [frameTick] heartbeat so
  /// pull-based UI reads a fully-updated frame.
  void _onFrameEnd() {
    sceneCommands.flush();
    _extraFrameEnd?.call();
    _frameTick.pulse();
  }

  final FrameTickNotifier _frameTick = FrameTickNotifier();

  /// A [Listenable] pulsed once at the end of every rendered frame — the
  /// presentation heartbeat for pull-based UI (an FPS counter, a live boss
  /// bar). It fires at `onFrameEnd`, after the `update`/`renderSync` schedules
  /// and the scene-command flush, so a listener that reads world state sees the
  /// frame already fully resolved. Prefer this (via `ListenableBuilder`) over
  /// pushing per-frame snapshots out of the world.
  Listenable get frameTick => _frameTick;

  /// Mounts newly bound nodes and flushes them. Runs at every command boundary
  /// (after `frameStart`, after each fixed step, after `postPhysics`, and
  /// after `update`) plus once
  /// at startup, so nodes spawned by any schedule are parented (and
  /// `Mounted`-tagged) before the next schedule runs — in particular, gameplay
  /// `update` systems always see already-mounted nodes.
  void _mountStep() {
    _mountAdapter.run();
    sceneCommands.flush();
    _extraCommandBoundary?.call();
  }

  bool _started = false;
  bool _shutdown = false;
  EcsSceneDriver? _driver;

  /// Optional layer hooks: [onCommandBoundary] runs at the end of every
  /// mount step (after the mount adapter and scene-command flush — where a
  /// layer above, like the Scripts runtime, applies its own deferred work);
  /// [onFrameEnd] runs at frame end after the scene-command flush, before
  /// the [frameTick] pulse.
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
         onDiagnostic: onDiagnostic,
         diagnostics: diagnostics,
       );

  /// A headless engine: the full pipeline — schedules, mounting, transform
  /// sync, the driver's self-driven fixed steps — over a standalone [root]
  /// node, with no [Scene] and no GPU. Constructing a real `Scene` requires
  /// Flutter GPU/Impeller, which `flutter test` does not provide; this is
  /// how integration logic runs under test ([onTick] drives the internal
  /// driver directly). No `Scene` resource is inserted.
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
         onDiagnostic: onDiagnostic,
         diagnostics: diagnostics,
       );

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

  /// Sends [event] to the channel for its runtime type, to be read by systems
  /// through `EventReader<T>` on the next frame.
  ///
  /// This is the path for Flutter to trigger gameplay from a widget callback
  /// (`onTap`, a key handler) without reaching into gameplay resources: emit an
  /// intent, let a scheduled system consume it. Events sent between frames survive
  /// into the next frame's readers (see the event retention window), so a tap is
  /// never dropped and is delivered exactly once.
  ///
  /// Routing is by [Object.runtimeType], deliberately *not* a static type
  /// argument: `dispatch(cond ? FireCanceled() : FireReleased())` would otherwise
  /// infer the type from the widened `cond ? ... : ...` expression (their common
  /// supertype) and deliver to a channel no system reads. The event's type must
  /// already be registered — a system reading `EventReader<T>` does this, or call
  /// `addEvent<T>()`.
  ///
  /// Use this for discrete intents. Continuous/held input (axes, hold-to-charge)
  /// belongs in a `ButtonInput` resource the widget writes directly.
  void dispatch(Object event) => world.sendEvent(event);

  /// Registers a state machine for [S], starting at [initial]. Mirrors
  /// [AppBuilder.addState]; transitions apply at the frame-start boundary.
  Game addState<S extends Object>(S initial) {
    app.addState<S>(initial);
    return this;
  }

  /// Declares the order of [sets] within [schedule]. Mirrors
  /// [AppBuilder.configureSets] — the composition root's half of system
  /// sets; plugins join sets with `addSystem(..., inSet: ...)`.
  Game configureSets(ScheduleLabel schedule, List<SystemSet> sets) {
    app.configureSets(schedule, sets);
    return this;
  }

  /// Inserts an externally-constructed resource (e.g. one the Flutter widget
  /// also holds) before [start]. The single authoring path for resources —
  /// fails loud on a duplicate; use [replaceResource] to swap intentionally.
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
    // Expose the real flutter_scene Scene and the deferred scene-command buffer
    // to systems via `@Resource()`. The integration wires flutter_scene in; it
    // does not wrap it — systems configure skybox/environment/lighting/etc. directly
    // on `@Resource() Scene`. A headless engine has no Scene to expose.
    final scene = this.scene;
    if (scene != null) app.world.resources.insert<Scene>(scene);
    app.world.resources
      ..insert<SceneCommands>(sceneCommands)
      ..insert<SceneNodeIndex>(SceneNodeIndex(_nodeIndex));
    // Standard integration system (renderSync): sync the standard SceneTransform
    // onto bound nodes after the gameplay `update` phase. Node mounting is *not*
    // a renderSync system — it runs before `update` (see _mountStep) so gameplay
    // sees mounted nodes — so a `@Bundle` can create its own node and simply
    // become visible.
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
    // Startup spawns flush before the initial OnEnter schedules run, so
    // enter systems see them exactly as a later transition would (the mount
    // adapter is not initialized yet — nodes mount at the _mountStep below).
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

  /// `SceneView.onTick` handler: runs frame-start work, then explicitly
  /// ticks the scene with the [GameClock]-scaled delta.
  ///
  /// Driving `Scene.update` here (instead of letting `Scene.render` take its
  /// implicit wall-clock tick) is what makes the clock authoritative: the
  /// physics accumulator, component updates, and animations all advance on
  /// scaled time, so `timeScale`/`paused`/`freezeFor` slow or halt physics
  /// and gameplay together. At scale `0` no fixed steps run at all.
  void onTick(Duration elapsed, double deltaSeconds) {
    final scaledDelta = _loop.frameStart(elapsed, deltaSeconds);
    final scene = this.scene;
    if (scene != null) {
      scene.update(scaledDelta);
    } else {
      // Headless: no scene walk, so dispatch the driver directly — its
      // self-driven accumulator supplies the fixed steps.
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
