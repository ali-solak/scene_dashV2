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

/// Available debug-draw colors.
enum DebugColor { green, red, blue, yellow }

/// Debug shapes for the current frame.
final class DebugDraw {
  /// Capacities are per color, per shape kind.
  DebugDraw({
    int sphereCapacity = 64,
    int lineCapacity = 128,
    int cuboidCapacity = 32,
  }) : buckets = List<DebugDrawBucket>.generate(
         DebugColor.values.length,
         (_) => DebugDrawBucket(
           sphereCapacity: sphereCapacity,
           lineCapacity: lineCapacity,
           cuboidCapacity: cuboidCapacity,
         ),
         growable: false,
       );

  /// Whether debug drawing is enabled.
  bool enabled = true;

  /// Shapes dropped this frame because a buffer was full.
  int droppedThisFrame = 0;

  /// Per color staging buffers.
  final List<DebugDrawBucket> buckets;

  // Scratch for ray's endpoint computation.
  static final Vector3 _end = Vector3.zero();

  /// A sphere of [radius] at [center].
  void sphere(
    Vector3 center,
    double radius, {
    DebugColor color = DebugColor.green,
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
    DebugColor color = DebugColor.green,
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
    DebugColor color = DebugColor.green,
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
    DebugColor color = DebugColor.green,
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
final class DebugDrawBucket {
  DebugDrawBucket({
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

/// Writes the transform for a debug line into [out]: a unit cube stretched
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

/// Installs debug shape rendering.
Feature installDebugDraw({
  int sphereCapacity = 64,
  int lineCapacity = 128,
  int cuboidCapacity = 32,
  bool enabled = true,
}) {
  return (game) {
    game.addPlugin(
      DebugDrawPlugin(
        sphereCapacity: sphereCapacity,
        lineCapacity: lineCapacity,
        cuboidCapacity: cuboidCapacity,
      ),
    );
    game.world.resources.get<DebugDraw>().enabled = enabled;
  };
}

/// Adds debug drawing to a game.
final class DebugDrawPlugin extends Plugin {
  /// Per-color, per-shape instance capacities for the [DebugDraw] resource.
  final int sphereCapacity;
  final int lineCapacity;
  final int cuboidCapacity;

  DebugDrawPlugin({
    this.sphereCapacity = 64,
    this.lineCapacity = 128,
    this.cuboidCapacity = 32,
  });

  @override
  void build(AppBuilder app) {
    final debugDraw = DebugDraw(
      sphereCapacity: sphereCapacity,
      lineCapacity: lineCapacity,
      cuboidCapacity: cuboidCapacity,
    );
    final flush = _DebugDrawFlushAdapter(debugDraw);
    app
      ..insertResource<DebugDraw>(debugDraw)
      ..addSystemAdapter(
        _DebugDrawClearAdapter(debugDraw),
        schedule: Schedules.frameStart,
        label: const SystemLabel('debugDraw.clear'),
      )
      ..addSystemAdapter(
        flush,
        schedule: Schedules.renderSync,
        label: const SystemLabel('debugDraw.flush'),
      );
  }
}

Vector4 _tint(DebugColor color) => switch (color) {
  DebugColor.green => Vector4(0.25, 1.0, 0.45, 0.4),
  DebugColor.red => Vector4(1.0, 0.3, 0.25, 0.4),
  DebugColor.blue => Vector4(0.35, 0.65, 1.0, 0.4),
  DebugColor.yellow => Vector4(1.0, 0.9, 0.25, 0.4),
};

final Matrix4 _hidden = Matrix4.diagonal3Values(0, 0, 0);

/// One instanced pool per shape kind. Color is per instance, so every
/// [DebugColor] shares a pool: three draws for the whole layer, not twelve.
final class _DebugDrawPools {
  // Keep debug geometry inexpensive.
  _DebugDrawPools(List<DebugDrawBucket> buckets)
    : spheres = _pool(
        IcosphereGeometry(radius: 1, subdivisions: 1),
        buckets.fold(0, (sum, b) => sum + b.sphereCapacity),
      ),
      lines = _pool(
        CuboidGeometry(Vector3(1, 1, 1)),
        buckets.fold(0, (sum, b) => sum + b.lineCapacity),
      ),
      cuboids = _pool(
        CuboidGeometry(Vector3(1, 1, 1)),
        buckets.fold(0, (sum, b) => sum + b.cuboidCapacity),
      );

  final InstancedMesh spheres;
  final InstancedMesh lines;
  final InstancedMesh cuboids;

  /// Instances written last frame, so this frame only hides its own residue.
  int lastSpheres = 0;
  int lastLines = 0;
  int lastCuboids = 0;

  static InstancedMesh _pool(Geometry geometry, int capacity) {
    // White base: the unlit shader multiplies it by the instance color.
    final material = UnlitMaterial()
      ..baseColorFactor = Vector4(1, 1, 1, 1)
      ..alphaMode = AlphaMode.blend;
    final mesh = InstancedMesh(
      geometry: geometry,
      material: material,
      // These blend, but the back-to-front sort buys nothing legible.
      sortTransparentInstances: false,
    );
    for (var i = 0; i < capacity; i++) {
      mesh.addInstance(_hidden);
    }
    return mesh;
  }

  /// Scene node containing the debug-draw pools.
  late final Node node;

  void addTo(Scene scene) {
    // These move every frame; culling bounds upkeep would be wasted work.
    node = Node()
      ..frustumCulled = false
      ..addComponent(InstancedMeshComponent(spheres))
      ..addComponent(InstancedMeshComponent(lines))
      ..addComponent(InstancedMeshComponent(cuboids));
    scene.root.add(node);
  }
}

final class _DebugDrawClearAdapter
    implements SystemAdapter, SystemAccessProvider {
  _DebugDrawClearAdapter(this._debugDraw);

  /// Reads no components.
  @override
  SystemAccess get access => SystemAccess.empty;

  final DebugDraw _debugDraw;

  @override
  void initialize(World world) {}

  @override
  void run() => _debugDraw.clear();
}

/// Writes this frame's submissions into the instanced pools and hides the
/// slots used last frame but not this one.
///
/// Colors are laid out in [DebugColor] order, each span starting where the
/// previous capacity ends, so a slot's tint is set once and never moves.
final class _DebugDrawFlushAdapter
    implements SystemAdapter, SystemAccessProvider {
  _DebugDrawFlushAdapter(this.debugDraw);

  /// Reads no components.
  @override
  SystemAccess get access => SystemAccess.empty;

  final DebugDraw debugDraw;
  _DebugDrawPools? pools;
  bool _poolsVisible = false;

  late World _world;

  @override
  void initialize(World world) => _world = world;

  @override
  void run() {
    if (!debugDraw.enabled) {
      _hideResidue();
      return;
    }
    var pools = this.pools;
    if (pools == null) {
      // Build pools on first use.
      final scene = _world.resources.tryGet<Scene>();
      if (scene == null) return;
      pools = _DebugDrawPools(debugDraw.buckets)..addTo(scene);
      _paintInstanceColors(pools);
      this.pools = pools;
    }
    if (!_poolsVisible) {
      pools.node.visible = true;
      _poolsVisible = true;
    }

    final buckets = debugDraw.buckets;
    pools.spheres.updateInstanceTransforms(recomputeWinding: false, (
      transforms,
    ) {
      var slot = 0;
      var written = 0;
      for (final bucket in buckets) {
        for (var i = 0; i < bucket.sphereCount; i++) {
          final base = i * 4;
          final r = bucket.spheres[base + 3];
          final out = transforms[slot + i]..setZero();
          final s = out.storage;
          s[0] = r;
          s[5] = r;
          s[10] = r;
          s[12] = bucket.spheres[base];
          s[13] = bucket.spheres[base + 1];
          s[14] = bucket.spheres[base + 2];
          s[15] = 1;
        }
        written += bucket.sphereCount;
        _hideRange(transforms, slot, bucket.sphereCount, bucket.sphereCapacity);
        slot += bucket.sphereCapacity;
      }
      pools!.lastSpheres = written;
    });

    pools.lines.updateInstanceTransforms(recomputeWinding: false, (transforms) {
      var slot = 0;
      var written = 0;
      for (final bucket in buckets) {
        for (var i = 0; i < bucket.lineCount; i++) {
          final base = i * 7;
          composeLineTransform(
            transforms[slot + i],
            bucket.lines[base],
            bucket.lines[base + 1],
            bucket.lines[base + 2],
            bucket.lines[base + 3],
            bucket.lines[base + 4],
            bucket.lines[base + 5],
            bucket.lines[base + 6],
          );
        }
        written += bucket.lineCount;
        _hideRange(transforms, slot, bucket.lineCount, bucket.lineCapacity);
        slot += bucket.lineCapacity;
      }
      pools!.lastLines = written;
    });

    pools.cuboids.updateInstanceTransforms(recomputeWinding: false, (
      transforms,
    ) {
      var slot = 0;
      var written = 0;
      for (final bucket in buckets) {
        for (var i = 0; i < bucket.cuboidCount; i++) {
          final base = i * 6;
          final out = transforms[slot + i]..setZero();
          final s = out.storage;
          s[0] = bucket.cuboids[base + 3] * 2;
          s[5] = bucket.cuboids[base + 4] * 2;
          s[10] = bucket.cuboids[base + 5] * 2;
          s[12] = bucket.cuboids[base];
          s[13] = bucket.cuboids[base + 1];
          s[14] = bucket.cuboids[base + 2];
          s[15] = 1;
        }
        written += bucket.cuboidCount;
        _hideRange(transforms, slot, bucket.cuboidCount, bucket.cuboidCapacity);
        slot += bucket.cuboidCapacity;
      }
      pools!.lastCuboids = written;
    });
  }

  /// Collapses the unwritten tail of one color's span to zero scale.
  static void _hideRange(
    List<Matrix4> transforms,
    int slot,
    int used,
    int capacity,
  ) {
    for (var i = used; i < capacity; i++) {
      transforms[slot + i].setFrom(_hidden);
    }
  }

  /// Tints every slot once; a slot keeps its color for the pool's lifetime.
  void _paintInstanceColors(_DebugDrawPools pools) {
    var sphereSlot = 0;
    var lineSlot = 0;
    var cuboidSlot = 0;
    for (var c = 0; c < DebugColor.values.length; c++) {
      final tint = _tint(DebugColor.values[c]);
      final bucket = debugDraw.buckets[c];
      for (var i = 0; i < bucket.sphereCapacity; i++) {
        pools.spheres.setInstanceColor(sphereSlot + i, tint);
      }
      sphereSlot += bucket.sphereCapacity;
      for (var i = 0; i < bucket.lineCapacity; i++) {
        pools.lines.setInstanceColor(lineSlot + i, tint);
      }
      lineSlot += bucket.lineCapacity;
      for (var i = 0; i < bucket.cuboidCapacity; i++) {
        pools.cuboids.setInstanceColor(cuboidSlot + i, tint);
      }
      cuboidSlot += bucket.cuboidCapacity;
    }
  }

  /// Hides what the last enabled frame wrote, then stops submitting the
  /// pool node entirely.
  void _hideResidue() {
    final pools = this.pools;
    if (pools == null || !_poolsVisible) return;
    if (pools.lastSpheres > 0) {
      pools.spheres.updateInstanceTransforms(
        recomputeWinding: false,
        (t) => _hideAll(t),
      );
      pools.lastSpheres = 0;
    }
    if (pools.lastLines > 0) {
      pools.lines.updateInstanceTransforms(
        recomputeWinding: false,
        (t) => _hideAll(t),
      );
      pools.lastLines = 0;
    }
    if (pools.lastCuboids > 0) {
      pools.cuboids.updateInstanceTransforms(
        recomputeWinding: false,
        (t) => _hideAll(t),
      );
      pools.lastCuboids = 0;
    }
    pools.node.visible = false;
    _poolsVisible = false;
  }

  static void _hideAll(List<Matrix4> transforms) {
    for (final transform in transforms) {
      transform.setFrom(_hidden);
    }
  }
}
