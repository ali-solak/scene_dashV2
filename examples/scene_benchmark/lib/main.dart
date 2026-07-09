import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_scene/scene.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';
// mountOnly hand-assembles the mount half of the driver from the machinery
// tier, so the mode isolates mounting cost from transform sync.
import 'package:scene_dash_v2_core/advanced.dart'
    show
        App,
        EcsFrameLoop,
        SystemAdapter,
        SystemLabel,
        SystemProfiler;
// Benchmark-only: mountOnly needs the same scene lifecycle driver as the
// booted game while intentionally skipping the built-in transform-sync
// registration.
// ignore: implementation_imports
import 'package:scene_dash_v2/src/scene_driver.dart';
import 'package:vector_math/vector_math.dart' as vm;

// Benchmark output is intentionally printed for `flutter run`/adb capture.
// ignore_for_file: avoid_print

const String _mode = String.fromEnvironment(
  'benchmarkMode',
  defaultValue: 'ecs',
);
const bool _profileSystems = bool.fromEnvironment(
  'profileSystems',
  defaultValue: false,
);
const int _gridSide = int.fromEnvironment('gridSide', defaultValue: 40);
const int _warmupFrames = int.fromEnvironment('warmupFrames', defaultValue: 90);
const int _sampleFrames = int.fromEnvironment(
  'sampleFrames',
  defaultValue: 240,
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Scene.initializeStaticResources();

  final benchmark = await SceneBenchmark.create(
    mode: BenchmarkMode.parse(_mode),
    gridSide: _gridSide,
  );
  runApp(SceneBenchmarkApp(benchmark: benchmark));
}

enum BenchmarkMode {
  staticNodes('static'),
  mountOnly('mountOnly'),
  ecs('ecs'),
  instanced('instanced');

  const BenchmarkMode(this.id);
  final String id;

  static BenchmarkMode parse(String value) {
    for (final mode in values) {
      if (mode.id == value) return mode;
    }
    throw ArgumentError.value(
      value,
      'benchmarkMode',
      'Expected static, mountOnly, ecs, or instanced.',
    );
  }
}

final class SceneBenchmark {
  SceneBenchmark._({
    required this.mode,
    required this.gridSide,
    required this.scene,
    required this.camera,
    this.game,
    this.mountOnlyRuntime,
  });

  final BenchmarkMode mode;
  final int gridSide;
  final Scene scene;
  final PerspectiveCamera camera;
  final SceneGame? game;
  final MountOnlyRuntime? mountOnlyRuntime;

  int get visibleCount => gridSide * gridSide;

  static Future<SceneBenchmark> create({
    required BenchmarkMode mode,
    required int gridSide,
  }) async {
    final scene = Scene()..directionalLight = DirectionalLight(intensity: 2.0);
    final camera = PerspectiveCamera(
      position: vm.Vector3(0, gridSide * 0.72, gridSide * 1.35),
      target: vm.Vector3.zero(),
      fovRadiansY: 42 * vm.degrees2Radians,
      fovFar: 1000,
    );
    final mesh = _cubeMesh();

    switch (mode) {
      case BenchmarkMode.staticNodes:
        _addStaticNodes(scene, mesh, gridSide);
        return SceneBenchmark._(
          mode: mode,
          gridSide: gridSide,
          scene: scene,
          camera: camera,
        );
      case BenchmarkMode.mountOnly:
        final runtime = MountOnlyRuntime(scene: scene)
          ..app.addSystemAdapter(
            _SpawnGridAdapter(mesh, gridSide, includeTransform: false),
            schedule: Schedules.startup,
            label: const SystemLabel('benchmark.spawnGrid'),
          );
        await runtime.start();
        return SceneBenchmark._(
          mode: mode,
          gridSide: gridSide,
          scene: scene,
          camera: camera,
          mountOnlyRuntime: runtime,
        );
      case BenchmarkMode.ecs:
        // The shipped path, exactly as a game boots it: `SceneGame.boot`
        // with a feature spawning the grid through the deferred world
        // verbs. The measured cost therefore includes everything boot
        // wires (mounting and transform sync; debug gizmos are opt-in and
        // not installed here).
        final game = await SceneGame.boot(
          scene: scene,
          diagnostics: const AppDiagnostics(profileSystems: _profileSystems),
          features: [
            (game) => game.addSystem(
                  Schedules.startup,
                  _spawnCubeGrid(mesh, gridSide),
                  writes: {SceneTransform, SceneNode},
                  label: 'benchmark.spawnGrid',
                ),
          ],
        );
        return SceneBenchmark._(
          mode: mode,
          gridSide: gridSide,
          scene: scene,
          camera: camera,
          game: game,
        );
      case BenchmarkMode.instanced:
        final instanced = InstancedMesh(
          geometry: mesh.primitives.single.geometry,
          material: mesh.primitives.single.material,
        );
        for (var i = 0; i < gridSide * gridSide; i++) {
          instanced.addInstance(_gridMatrix(i, gridSide));
        }
        scene.root.add(Node()..addComponent(InstancedMeshComponent(instanced)));
        return SceneBenchmark._(
          mode: mode,
          gridSide: gridSide,
          scene: scene,
          camera: camera,
        );
    }
  }

  void tick(Duration elapsed, double deltaSeconds) {
    game?.onTick(elapsed, deltaSeconds);
    mountOnlyRuntime?.onTick(elapsed, deltaSeconds);
  }

  void resetProfiler() {
    game?.engine.profiler?.reset();
    mountOnlyRuntime?.profiler?.reset();
  }

  SystemProfiler? get profiler =>
      game?.engine.profiler ?? mountOnlyRuntime?.profiler;

  Future<void> dispose() async {
    await game?.shutdown();
    await mountOnlyRuntime?.shutdown();
  }
}

/// The ECS lifecycle and node mounting with **no** transform sync: what a
/// game pays for entity-bound nodes alone. Hand-assembled from the
/// machinery tier because the booted game always registers sync — this
/// mode exists precisely to subtract it.
final class MountOnlyRuntime {
  MountOnlyRuntime({required this.scene})
      : app = App(
          diagnostics: const AppDiagnostics(profileSystems: _profileSystems),
        );

  final Scene scene;
  final App app;

  late final SceneCommands sceneCommands = SceneCommands(scene.root);
  final Map<Node, Entity> _nodeIndex = <Node, Entity>{};
  late final SceneNodeMountAdapter _mountAdapter = SceneNodeMountAdapter(
    sceneCommands,
    _nodeIndex,
  );
  late final EcsFrameLoop _loop = EcsFrameLoop(
    app,
    onCommandBoundary: _mountStep,
    onFrameEnd: sceneCommands.flush,
  );
  EcsSceneDriver? _driver;

  SystemProfiler? get profiler => app.profiler;

  Future<void> start() async {
    _loop.ensureTimeResources();
    app.world.resources
      ..insert<Scene>(scene)
      ..insert<SceneCommands>(sceneCommands)
      ..insert<SceneNodeIndex>(SceneNodeIndex(_nodeIndex));
    app.start();
    _mountAdapter.initialize(app.world);
    _mountStep();
    final driver = EcsSceneDriver(_loop);
    scene.root.addComponent(driver);
    _driver = driver;
  }

  void onTick(Duration elapsed, double deltaSeconds) {
    _loop.frameStart(elapsed, deltaSeconds);
  }

  Future<void> shutdown() async {
    await app.shutdown();
    final driver = _driver;
    if (driver != null) {
      scene.root.removeComponent(driver);
      _driver = null;
    }
    sceneCommands.flush();
  }

  void _mountStep() {
    _mountAdapter.run();
    sceneCommands.flush();
  }
}

class SceneBenchmarkApp extends StatefulWidget {
  const SceneBenchmarkApp({super.key, required this.benchmark});

  final SceneBenchmark benchmark;

  @override
  State<SceneBenchmarkApp> createState() => _SceneBenchmarkAppState();
}

class _SceneBenchmarkAppState extends State<SceneBenchmarkApp> {
  final List<FrameTiming> _measured = <FrameTiming>[];
  late final TimingsCallback _timingsCallback;
  int _warmupSeen = 0;
  bool _sampling = false;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _timingsCallback = _onTimings;
    SchedulerBinding.instance.addTimingsCallback(_timingsCallback);
    _printConfig();
  }

  @override
  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(_timingsCallback);
    unawaited(widget.benchmark.dispose());
    super.dispose();
  }

  void _onTimings(List<FrameTiming> timings) {
    if (_finished) return;
    for (final timing in timings) {
      if (!_sampling) {
        _warmupSeen++;
        if (_warmupSeen < _warmupFrames) continue;
        widget.benchmark.resetProfiler();
        _sampling = true;
        continue;
      }

      _measured.add(timing);
      if (_measured.length >= _sampleFrames) {
        _finished = true;
        _printSummary();
        unawaited(widget.benchmark.dispose().then((_) => exit(0)));
        return;
      }
    }
  }

  void _printConfig() {
    final benchmark = widget.benchmark;
    print(
      'SCENE_BENCHMARK config '
      'mode=${benchmark.mode.id} '
      'profileSystems=$_profileSystems '
      'gridSide=${benchmark.gridSide} '
      'visible=${benchmark.visibleCount} '
      'warmupFrames=$_warmupFrames '
      'sampleFrames=$_sampleFrames',
    );
  }

  void _printSummary() {
    final builds =
        _measured
            .map((t) => t.buildDuration.inMicroseconds / 1000)
            .toList(growable: false)
          ..sort();
    final rasters =
        _measured
            .map((t) => t.rasterDuration.inMicroseconds / 1000)
            .toList(growable: false)
          ..sort();

    print(
      'SCENE_BENCHMARK result '
      'mode=${widget.benchmark.mode.id} '
      'profileSystems=$_profileSystems '
      'frames=${_measured.length} '
      'build_median_ms=${_percentile(builds, 0.50).toStringAsFixed(3)} '
      'build_p95_ms=${_percentile(builds, 0.95).toStringAsFixed(3)} '
      'raster_median_ms=${_percentile(rasters, 0.50).toStringAsFixed(3)} '
      'raster_p95_ms=${_percentile(rasters, 0.95).toStringAsFixed(3)}',
    );

    _printSystemTimings(widget.benchmark.mode, widget.benchmark.profiler);
  }

  @override
  Widget build(BuildContext context) {
    final benchmark = widget.benchmark;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: ColoredBox(
        color: Colors.black,
        child: SceneView(
          benchmark.scene,
          camera: benchmark.camera,
          onTick: benchmark.tick,
        ),
      ),
    );
  }
}

/// The ecs mode's spawner: the surface idiom — a startup system spawning
/// bundle lists through the deferred world verbs.
WorldSystem _spawnCubeGrid(Mesh mesh, int gridSide) {
  return (world) {
    for (var i = 0; i < gridSide * gridSide; i++) {
      final matrix = _gridMatrix(i, gridSide);
      world.spawn([
        SceneTransform.trs(
          translation: matrix.getTranslation(),
          scale: vm.Vector3.all(1),
        ),
        SceneNode(Node(mesh: mesh, localTransform: matrix)),
      ]);
    }
  };
}

/// The mountOnly mode's spawner: machinery-tier immediate inserts, so the
/// hand-rolled runtime needs no spawn-queue wiring.
final class _SpawnGridAdapter implements SystemAdapter {
  _SpawnGridAdapter(this.mesh, this.gridSide, {required this.includeTransform});

  final Mesh mesh;
  final int gridSide;
  final bool includeTransform;
  late World _world;

  @override
  void initialize(World world) {
    _world = world;
    world.ensureObjectStore<SceneNode>();
    if (includeTransform) world.ensureObjectStore<SceneTransform>();
  }

  @override
  void run() {
    for (var i = 0; i < gridSide * gridSide; i++) {
      final matrix = _gridMatrix(i, gridSide);
      final entity = _world.entities.spawn();
      if (includeTransform) {
        _world.insertNow<SceneTransform>(
          entity,
          SceneTransform.trs(
            translation: matrix.getTranslation(),
            scale: vm.Vector3.all(1),
          ),
        );
      }
      _world.insertNow<SceneNode>(
        entity,
        SceneNode(Node(mesh: mesh, localTransform: matrix)),
      );
    }
  }
}

Mesh _cubeMesh() {
  final material = UnlitMaterial()
    ..baseColorFactor = vm.Vector4(0.25, 0.85, 1.0, 1.0);
  return Mesh(CuboidGeometry(vm.Vector3.all(0.48)), material);
}

void _addStaticNodes(Scene scene, Mesh mesh, int gridSide) {
  for (var i = 0; i < gridSide * gridSide; i++) {
    scene.root.add(Node(mesh: mesh, localTransform: _gridMatrix(i, gridSide)));
  }
}

vm.Matrix4 _gridMatrix(int index, int gridSide) {
  final x = (index % gridSide) - (gridSide - 1) * 0.5;
  final z = (index ~/ gridSide) - (gridSide - 1) * 0.5;
  return vm.Matrix4.translationValues(x * 0.72, 0, z * 0.72);
}

double _percentile(List<double> sorted, double p) {
  if (sorted.isEmpty) return 0;
  final raw = (sorted.length - 1) * p;
  final low = raw.floor();
  final high = raw.ceil();
  if (low == high) return sorted[low];
  final t = raw - low;
  return sorted[low] * (1 - t) + sorted[high] * t;
}

void _printSystemTimings(BenchmarkMode mode, SystemProfiler? profiler) {
  if (profiler == null) return;
  for (final timing in profiler.timings) {
    print(
      'SCENE_BENCHMARK system '
      'mode=${mode.id} '
      'profileSystems=$_profileSystems '
      'schedule=${timing.schedule.id} '
      'system=${timing.label.id} '
      'runs=${timing.runs} '
      'latest_us=${timing.latestMicros} '
      'avg_us=${(timing.totalMicros / timing.runs).toStringAsFixed(3)} '
      'max_us=${timing.maxMicros}',
    );
  }
}
