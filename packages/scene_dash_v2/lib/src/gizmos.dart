import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_scene/scene.dart'
    show
        AlphaMode,
        CuboidGeometry,
        Geometry,
        IcosphereGeometry,
        InstancedMesh,
        InstancedMeshComponent,
        Node,
        Scene,
        UnlitMaterial;
import 'package:scene_dash_v2_core/advanced.dart';
import 'package:vector_math/vector_math.dart';

/// The fixed gizmo palette. `flutter_scene` instancing is transform-only
/// (no per-instance color, still true in 0.19), so each color is its own
/// instanced pool and arbitrary per-call colors are not offered.
enum GizmoColor { green, red, blue, yellow }

/// Immediate-mode debug drawing: any system submits shapes for the current
/// frame; nothing persists.
///
/// A resource inserted by [GizmosPlugin]; inject with `@Resource()`:
///
/// ```dart
/// @System()
/// void probeGround(@Resource() Gizmos gizmos, ...) {
///   gizmos.ray(origin, down, groundProbeDistance, color: GizmoColor.yellow);
///   gizmos.sphere(playerPos, hitRadius, color: GizmoColor.red);
/// }
/// ```
///
/// Submissions are cleared at frame start and flushed into instanced meshes
/// at `renderSync`, so a shape submitted from any schedule draws for exactly
/// that frame. Calls write plain floats into fixed-capacity buffers — no
/// allocation — and become no-ops while [enabled] is `false`, so call sites
/// can stay in shipping code. Overflow past a shape's capacity drops the
/// shape and counts it in [droppedThisFrame].
final class Gizmos {
  /// Capacities are per color, per shape kind.
  Gizmos({
    int sphereCapacity = 64,
    int lineCapacity = 128,
    int cuboidCapacity = 32,
  }) : buckets = List<GizmoBucket>.generate(
         GizmoColor.values.length,
         (_) => GizmoBucket(
           sphereCapacity: sphereCapacity,
           lineCapacity: lineCapacity,
           cuboidCapacity: cuboidCapacity,
         ),
         growable: false,
       );

  /// Master switch: while `false`, every submission returns immediately.
  ///
  /// It also controls rendering, but as a *startup* decision: [GizmosPlugin]
  /// only builds and attaches the instanced pools when this is `true` at the
  /// time the setup system runs, so a disabled game pays no per-frame draw
  /// cost. Set it before `start()`; toggling it at runtime affects
  /// submissions but not whether the pools exist.
  bool enabled = true;

  /// Shapes dropped this frame because a buffer was full.
  int droppedThisFrame = 0;

  /// Per-color staging buffers, indexed by [GizmoColor.index]. Read by the
  /// flush system; not part of the public API surface.
  final List<GizmoBucket> buckets;

  // Scratch for ray's endpoint computation.
  static final Vector3 _end = Vector3.zero();

  /// A sphere of [radius] at [center].
  void sphere(
    Vector3 center,
    double radius, {
    GizmoColor color = GizmoColor.green,
  }) {
    if (!enabled) return;
    final b = buckets[color.index];
    if (b.sphereCount >= b.sphereCapacity) {
      droppedThisFrame++;
      return;
    }
    final i = b.sphereCount * 4;
    b.spheres[i] = center.x;
    b.spheres[i + 1] = center.y;
    b.spheres[i + 2] = center.z;
    b.spheres[i + 3] = radius;
    b.sphereCount++;
  }

  /// A segment from [a] to [b], drawn as a thin box of [thickness].
  void line(
    Vector3 a,
    Vector3 b, {
    double thickness = 0.02,
    GizmoColor color = GizmoColor.green,
  }) {
    if (!enabled) return;
    final bucket = buckets[color.index];
    if (bucket.lineCount >= bucket.lineCapacity) {
      droppedThisFrame++;
      return;
    }
    final i = bucket.lineCount * 7;
    final lines = bucket.lines;
    lines[i] = a.x;
    lines[i + 1] = a.y;
    lines[i + 2] = a.z;
    lines[i + 3] = b.x;
    lines[i + 4] = b.y;
    lines[i + 5] = b.z;
    lines[i + 6] = thickness;
    bucket.lineCount++;
  }

  /// A segment of [length] from [origin] along [direction] (normalized
  /// internally).
  void ray(
    Vector3 origin,
    Vector3 direction,
    double length, {
    double thickness = 0.02,
    GizmoColor color = GizmoColor.green,
  }) {
    if (!enabled) return;
    _end
      ..setFrom(direction)
      ..normalize()
      ..scale(length)
      ..add(origin);
    line(origin, _end, thickness: thickness, color: color);
  }

  /// An axis-aligned box at [center] with [halfExtents].
  void cuboid(
    Vector3 center,
    Vector3 halfExtents, {
    GizmoColor color = GizmoColor.green,
  }) {
    if (!enabled) return;
    final b = buckets[color.index];
    if (b.cuboidCount >= b.cuboidCapacity) {
      droppedThisFrame++;
      return;
    }
    final i = b.cuboidCount * 6;
    b.cuboids[i] = center.x;
    b.cuboids[i + 1] = center.y;
    b.cuboids[i + 2] = center.z;
    b.cuboids[i + 3] = halfExtents.x;
    b.cuboids[i + 4] = halfExtents.y;
    b.cuboids[i + 5] = halfExtents.z;
    b.cuboidCount++;
  }

  /// Drops all submissions. Called by the plugin at frame start.
  void clear() {
    for (final bucket in buckets) {
      bucket.sphereCount = 0;
      bucket.lineCount = 0;
      bucket.cuboidCount = 0;
    }
    droppedThisFrame = 0;
  }
}

/// One color's staging buffers. Packed float layouts:
/// spheres `x,y,z,radius`; lines `ax,ay,az,bx,by,bz,thickness`;
/// cuboids `cx,cy,cz,hx,hy,hz`.
final class GizmoBucket {
  GizmoBucket({
    required this.sphereCapacity,
    required this.lineCapacity,
    required this.cuboidCapacity,
  }) : spheres = Float32List(sphereCapacity * 4),
       lines = Float32List(lineCapacity * 7),
       cuboids = Float32List(cuboidCapacity * 6);

  final int sphereCapacity;
  final int lineCapacity;
  final int cuboidCapacity;

  final Float32List spheres;
  final Float32List lines;
  final Float32List cuboids;

  int sphereCount = 0;
  int lineCount = 0;
  int cuboidCount = 0;
}

/// Writes the transform for a line gizmo into [out]: a unit cube stretched
/// to span `a -> b` with square cross-section [thickness]. A degenerate
/// segment (zero length) collapses to zero scale.
///
/// Public for tests; the flush system is its only production caller.
@visibleForTesting
void composeLineTransform(
  Matrix4 out,
  double ax,
  double ay,
  double az,
  double bx,
  double by,
  double bz,
  double thickness,
) {
  var fx = bx - ax, fy = by - ay, fz = bz - az;
  final length = Vector3(fx, fy, fz).length;
  final s = out.storage;
  if (length < 1e-9) {
    out.setZero();
    s[15] = 1;
    return;
  }
  fx /= length;
  fy /= length;
  fz /= length;
  // right = worldUp x forward; degenerate (vertical line) falls back to +X.
  var rx = 1.0 * fz - 0.0 * fy; // (0,1,0) x f
  var ry = 0.0 * fx - 0.0 * fz;
  var rz = 0.0 * fy - 1.0 * fx;
  final rLen2 = rx * rx + ry * ry + rz * rz;
  if (rLen2 < 1e-12) {
    rx = 1;
    ry = 0;
    rz = 0;
  } else {
    final inv = 1 / Vector3(rx, ry, rz).length;
    rx *= inv;
    ry *= inv;
    rz *= inv;
  }
  // up = forward x right (already unit-length).
  final ux = fy * rz - fz * ry;
  final uy = fz * rx - fx * rz;
  final uz = fx * ry - fy * rx;

  s[0] = rx * thickness;
  s[1] = ry * thickness;
  s[2] = rz * thickness;
  s[3] = 0;
  s[4] = ux * thickness;
  s[5] = uy * thickness;
  s[6] = uz * thickness;
  s[7] = 0;
  s[8] = fx * length;
  s[9] = fy * length;
  s[10] = fz * length;
  s[11] = 0;
  s[12] = (ax + bx) * 0.5;
  s[13] = (ay + by) * 0.5;
  s[14] = (az + bz) * 0.5;
  s[15] = 1;
}

/// The debug-gizmo render layer as a feature — opt-in, actively added:
///
/// ```dart
/// final game = await SceneGame.boot(
///   features: [installGizmos(enabled: showDebugGizmos), installPlayer, ...],
/// );
/// ```
///
/// Installs the [Gizmos] resource and the clear/flush systems. Pools build
/// lazily on the first *enabled* flush, so [enabled] — and
/// `world.gizmos.enabled` at any later moment — is a true runtime toggle:
/// off means zero draw calls and zero vertex work, on builds (or re-shows)
/// the pools that frame. Without this feature, `world.gizmos` is a disabled
/// recorder — submission calls in shipping code stay safe no-ops and
/// nothing is ever drawn.
Feature installGizmos({
  int sphereCapacity = 64,
  int lineCapacity = 128,
  int cuboidCapacity = 32,
  bool enabled = true,
}) {
  return (game) {
    game.addPlugin(
      GizmosPlugin(
        sphereCapacity: sphereCapacity,
        lineCapacity: lineCapacity,
        cuboidCapacity: cuboidCapacity,
      ),
    );
    game.world.resources.get<Gizmos>().enabled = enabled;
  };
}

/// Immediate-mode debug drawing for scene_dash games — the classic-plugin
/// form of [installGizmos].
///
/// Inserts the [Gizmos] resource, clears submissions each frame start and
/// flushes them into per-[GizmoColor], per-shape instanced pools at
/// `renderSync`. Pools draw depth-tested, unlit and semi-transparent, so
/// gizmos read against the scene without a dedicated overlay pass. The
/// pools are built lazily on the first flush that finds [Gizmos.enabled]
/// `true` (and hidden again whenever it goes `false`), so the flag is a
/// runtime toggle and a disabled layer costs nothing per frame.
final class GizmosPlugin extends Plugin {
  /// Per-color, per-shape instance capacities for the [Gizmos] resource.
  final int sphereCapacity;
  final int lineCapacity;
  final int cuboidCapacity;

  GizmosPlugin({
    this.sphereCapacity = 64,
    this.lineCapacity = 128,
    this.cuboidCapacity = 32,
  });

  @override
  void build(AppBuilder app) {
    final gizmos = Gizmos(
      sphereCapacity: sphereCapacity,
      lineCapacity: lineCapacity,
      cuboidCapacity: cuboidCapacity,
    );
    final flush = _GizmoFlushAdapter(gizmos);
    app
      ..insertResource<Gizmos>(gizmos)
      ..addSystemAdapter(
        _GizmoClearAdapter(gizmos),
        schedule: Schedules.frameStart,
        label: const SystemLabel('gizmos.clear'),
      )
      ..addSystemAdapter(
        flush,
        schedule: Schedules.renderSync,
        label: const SystemLabel('gizmos.flush'),
      );
  }
}

Vector4 _tint(GizmoColor color) => switch (color) {
  GizmoColor.green => Vector4(0.25, 1.0, 0.45, 0.4),
  GizmoColor.red => Vector4(1.0, 0.3, 0.25, 0.4),
  GizmoColor.blue => Vector4(0.35, 0.65, 1.0, 0.4),
  GizmoColor.yellow => Vector4(1.0, 0.9, 0.25, 0.4),
};

final Matrix4 _hidden = Matrix4.diagonal3Values(0, 0, 0);

/// One color's three instanced meshes.
final class _GizmoPools {
  // Debug-grade tessellation: instanced draws pay vertex cost for the whole
  // pool capacity (hidden zero-scale instances included), so a dense sphere
  // turns thousands of gizmos into millions of debug triangles. The 0.19
  // geodesic icosphere at one subdivision (80 triangles, evenly
  // distributed) reads rounder than a low-segment UV sphere at the same
  // vertex cost.
  //
  // Lines deliberately stay stretched unit cuboids rather than 0.19's
  // LineSegmentsGeometry: that geometry bakes its endpoints into a GPU
  // buffer at construction with no update path, so an immediate-mode layer
  // would have to rebuild geometry (and allocate a device buffer) every
  // frame — breaking this layer's no-per-frame-allocation contract.
  // Revisit when upstream ships an updatable segment batch (backlog row).
  _GizmoPools(GizmoColor color, GizmoBucket bucket)
    : spheres = _pool(
        IcosphereGeometry(radius: 1, subdivisions: 1),
        color,
        bucket.sphereCapacity,
      ),
      lines = _pool(
        CuboidGeometry(Vector3(1, 1, 1)),
        color,
        bucket.lineCapacity,
      ),
      cuboids = _pool(
        CuboidGeometry(Vector3(1, 1, 1)),
        color,
        bucket.cuboidCapacity,
      );

  final InstancedMesh spheres;
  final InstancedMesh lines;
  final InstancedMesh cuboids;

  int lastSpheres = 0;
  int lastLines = 0;
  int lastCuboids = 0;

  static InstancedMesh _pool(
    Geometry geometry,
    GizmoColor color,
    int capacity,
  ) {
    final material = UnlitMaterial()
      ..baseColorFactor = _tint(color)
      ..alphaMode = AlphaMode.blend;
    final mesh = InstancedMesh(geometry: geometry, material: material);
    for (var i = 0; i < capacity; i++) {
      mesh.addInstance(_hidden);
    }
    return mesh;
  }

  /// The pools' scene node; the flush toggles its visibility with
  /// [Gizmos.enabled] so a disabled layer submits no draws at all.
  late final Node node;

  void addTo(Scene scene) {
    // Gizmos move every frame; culling bounds upkeep would be wasted work.
    node = Node()
      ..frustumCulled = false
      ..addComponent(InstancedMeshComponent(spheres))
      ..addComponent(InstancedMeshComponent(lines))
      ..addComponent(InstancedMeshComponent(cuboids));
    scene.root.add(node);
  }
}

final class _GizmoClearAdapter implements SystemAdapter, SystemAccessProvider {
  _GizmoClearAdapter(this._gizmos);

  /// Touches only the [Gizmos] resource, which the access model does not
  /// cover — declared empty deliberately, not left to the fallback.
  @override
  SystemAccess get access => SystemAccess.empty;

  final Gizmos _gizmos;

  @override
  void initialize(World world) {}

  @override
  void run() => _gizmos.clear();
}

/// Writes this frame's submissions into the instanced pools and hides the
/// slots used last frame but not this one.
final class _GizmoFlushAdapter implements SystemAdapter, SystemAccessProvider {
  _GizmoFlushAdapter(this.gizmos);

  /// Touches only the [Gizmos] resource and its instanced pools, which the
  /// access model does not cover — declared empty deliberately, not left to
  /// the fallback.
  @override
  SystemAccess get access => SystemAccess.empty;

  final Gizmos gizmos;
  List<_GizmoPools>? pools;
  bool _poolsVisible = false;

  final Matrix4 _scratch = Matrix4.identity();

  late World _world;

  @override
  void initialize(World world) => _world = world;

  @override
  void run() {
    if (!gizmos.enabled) {
      _hideResidue();
      return;
    }
    var pools = this.pools;
    if (pools == null) {
      // Lazy: built on the first *enabled* flush, so `enabled` is a runtime
      // toggle rather than a startup decision. Headless worlds (no Scene)
      // stay record-only.
      final scene = _world.resources.tryGet<Scene>();
      if (scene == null) return;
      pools = List<_GizmoPools>.generate(
        GizmoColor.values.length,
        (i) => _GizmoPools(GizmoColor.values[i], gizmos.buckets[i]),
        growable: false,
      );
      for (final pool in pools) {
        pool.addTo(scene);
      }
      this.pools = pools;
    }
    if (!_poolsVisible) {
      for (final pool in pools) {
        pool.node.visible = true;
      }
      _poolsVisible = true;
    }
    for (var c = 0; c < pools.length; c++) {
      final bucket = gizmos.buckets[c];
      final pool = pools[c];

      for (var i = 0; i < bucket.sphereCount; i++) {
        final base = i * 4;
        final r = bucket.spheres[base + 3];
        final s = _scratch.storage;
        _scratch.setZero();
        s[0] = r;
        s[5] = r;
        s[10] = r;
        s[12] = bucket.spheres[base];
        s[13] = bucket.spheres[base + 1];
        s[14] = bucket.spheres[base + 2];
        s[15] = 1;
        pool.spheres.setInstanceTransform(i, _scratch);
      }
      for (var i = bucket.sphereCount; i < pool.lastSpheres; i++) {
        pool.spheres.setInstanceTransform(i, _hidden);
      }
      pool.lastSpheres = bucket.sphereCount;

      for (var i = 0; i < bucket.lineCount; i++) {
        final base = i * 7;
        composeLineTransform(
          _scratch,
          bucket.lines[base],
          bucket.lines[base + 1],
          bucket.lines[base + 2],
          bucket.lines[base + 3],
          bucket.lines[base + 4],
          bucket.lines[base + 5],
          bucket.lines[base + 6],
        );
        pool.lines.setInstanceTransform(i, _scratch);
      }
      for (var i = bucket.lineCount; i < pool.lastLines; i++) {
        pool.lines.setInstanceTransform(i, _hidden);
      }
      pool.lastLines = bucket.lineCount;

      for (var i = 0; i < bucket.cuboidCount; i++) {
        final base = i * 6;
        final s = _scratch.storage;
        _scratch.setZero();
        s[0] = bucket.cuboids[base + 3] * 2;
        s[5] = bucket.cuboids[base + 4] * 2;
        s[10] = bucket.cuboids[base + 5] * 2;
        s[12] = bucket.cuboids[base];
        s[13] = bucket.cuboids[base + 1];
        s[14] = bucket.cuboids[base + 2];
        s[15] = 1;
        pool.cuboids.setInstanceTransform(i, _scratch);
      }
      for (var i = bucket.cuboidCount; i < pool.lastCuboids; i++) {
        pool.cuboids.setInstanceTransform(i, _hidden);
      }
      pool.lastCuboids = bucket.cuboidCount;
    }
  }

  /// Disabled with pools built earlier: hide the slots the last enabled
  /// frame wrote (once), then stop submitting the pool nodes entirely.
  void _hideResidue() {
    final pools = this.pools;
    if (pools == null || !_poolsVisible) return;
    for (final pool in pools) {
      for (var i = 0; i < pool.lastSpheres; i++) {
        pool.spheres.setInstanceTransform(i, _hidden);
      }
      pool.lastSpheres = 0;
      for (var i = 0; i < pool.lastLines; i++) {
        pool.lines.setInstanceTransform(i, _hidden);
      }
      pool.lastLines = 0;
      for (var i = 0; i < pool.lastCuboids; i++) {
        pool.cuboids.setInstanceTransform(i, _hidden);
      }
      pool.lastCuboids = 0;
      pool.node.visible = false;
    }
    _poolsVisible = false;
  }
}
