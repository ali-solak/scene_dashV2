library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart'
    show Matrix4, Quaternion, Vector3, Vector4;

import '../data/config.dart'
    show
        cliffAzimuth,
        cliffHalfAngle,
        cliffRockCount,
        cliffRockMaxScale,
        cliffRockMinScale,
        cliffRockRadialSpread,
        cliffRockSpike,
        groundIslandRadius,
        oceanLevel;
import '../data/layout.dart';

// --- Dimensions (world units; placements add scale + yaw on top) ---
const double _trunkHeight = 2.2;
const double _trunkBottomRadius = 0.3;
const double _trunkTopRadius = 0.2;
const double _coneHeight = 2.2;
const double _coneStep = 1.15;
const double _canopyBaseY = 1.6;
const List<double> _coneRadii = [2.0, 1.55, 1.1];
const double _rockRadius = 0.7;
const double _bushRadius = 0.55;

// --- Tones, baked per vertex so one material paints the whole ring ---
final Vector4 _trunkTone = Vector4(0.36, 0.25, 0.16, 1);
// A few canopy tones so the ring reads as many trees, not one copy.
const List<(double, double, double)> _canopyTones = [
  (0.20, 0.34, 0.15),
  (0.16, 0.30, 0.18),
  (0.25, 0.38, 0.14),
];
final Vector4 _rockTone = Vector4(0.45, 0.44, 0.42, 1);
final Vector4 _bushTone = Vector4(0.18, 0.30, 0.14, 1);
// The cliff boulders read wet and in shadow: darker and cooler.
final Vector4 _cliffRockTone = Vector4(0.24, 0.25, 0.28, 1);

/// Bakes [placements] into one mesh node. The vertices land in the node's
/// local space (which is the clearing's, at the origin), so the returned
/// node needs no transform of its own.
Node buildForestBatch(List<PropPlacement> placements) {
  // Base shapes, built once and read back on the CPU. Fixed-storage shape
  // geometries retain their attributes at construction, so `extractMeshData`
  // works before the first draw. Kept low-poly; this is background dressing.
  final trunk = _shape(
    CylinderGeometry(
      bottomRadius: _trunkBottomRadius,
      topRadius: _trunkTopRadius,
      height: _trunkHeight,
      radialSegments: 6,
    ),
  );
  final cones = [
    for (final radius in _coneRadii)
      _shape(
        CylinderGeometry(
          bottomRadius: radius,
          topRadius: 0.02,
          height: _coneHeight,
          radialSegments: 6,
          topCap: false,
        ),
      ),
  ];
  final rock = _shape(IcosphereGeometry(radius: _rockRadius, subdivisions: 1));
  final bush = _shape(IcosphereGeometry(radius: _bushRadius, subdivisions: 1));

  final mesher = _Mesher();
  for (final placement in placements) {
    final base = Matrix4.compose(
      Vector3(placement.x, 0, placement.z),
      Quaternion.axisAngle(Vector3(0, 1, 0), placement.yaw),
      Vector3.all(placement.scale),
    );
    switch (placement.kind) {
      case PropKind.tree:
        mesher.add(
          trunk,
          base * Matrix4.translation(Vector3(0, _trunkHeight / 2, 0)),
          _trunkTone,
        );
        final t =
            _canopyTones[(placement.variantRoll * _canopyTones.length).floor() %
                _canopyTones.length];
        final canopy = Vector4(t.$1, t.$2, t.$3, 1);
        for (var i = 0; i < _coneRadii.length; i++) {
          mesher.add(
            cones[i],
            base *
                Matrix4.translation(
                  Vector3(0, _canopyBaseY + i * _coneStep + _coneHeight / 2, 0),
                ),
            canopy,
          );
        }
      case PropKind.rock:
        final squash = 0.6 + 0.4 * placement.variantRoll;
        mesher.add(
          rock,
          base *
              Matrix4.translation(Vector3(0, _rockRadius * squash * 0.8, 0)) *
              Matrix4.diagonal3(Vector3(1, squash, 1)),
          _rockTone,
        );
      case PropKind.bush:
        final squash = 0.55 + 0.25 * placement.variantRoll;
        mesher.add(
          bush,
          base *
              Matrix4.translation(Vector3(0, _bushRadius * squash * 0.75, 0)) *
              Matrix4.diagonal3(Vector3(1.15, squash, 1.15)),
          _bushTone,
        );
    }
  }
  return mesher.toNode('forest');
}

/// Big wet boulders and sea stacks massed at the foot of the cliff in the
/// treeline gap, where the surf breaks. One baked mesh, like the ring.
/// Deterministic from a fixed seed so they stand in the same place each run.
Node buildCliffRocks() {
  // A unit sphere at one subdivision: few, big facets, so the radial jag
  // reads as bold crags rather than fine noise (and it stays cheap).
  final rock = _shape(IcosphereGeometry(radius: 1, subdivisions: 1));
  final rng = math.Random(41);
  final mesher = _Mesher();
  for (var i = 0; i < cliffRockCount; i++) {
    final theta =
        cliffAzimuth + (rng.nextDouble() - 0.5) * 2 * cliffHalfAngle * 0.9;
    final radius =
        groundIslandRadius + (rng.nextDouble() - 0.5) * cliffRockRadialSpread;
    // Down the cliff face: most sit in the surf below the rim, and only the
    // tallest stacks poke up into view from the isle above.
    final y = oceanLevel - 3.5 + rng.nextDouble() * 5.5;
    final size =
        cliffRockMinScale +
        rng.nextDouble() * (cliffRockMaxScale - cliffRockMinScale);
    final squashY = 0.7 + rng.nextDouble() * 0.6;
    mesher.add(
      rock,
      Matrix4.compose(
        Vector3(math.sin(theta) * radius, y, math.cos(theta) * radius),
        Quaternion.axisAngle(Vector3(0, 1, 0), rng.nextDouble() * 2 * math.pi),
        Vector3(size, size * squashY, size),
      ),
      _cliffRockTone,
      jag: rng,
      jagAmount: cliffRockSpike,
    );
  }
  return mesher.toNode('cliff-rocks');
}

/// Accumulates transformed, vertex-coloured copies of base shapes into one
/// merged, lit mesh.
class _Mesher {
  final _positions = <double>[];
  final _colors = <double>[];
  final _indices = <int>[];

  void add(
    _Shape src,
    Matrix4 transform,
    Vector4 tone, {
    math.Random? jag,
    double jagAmount = 0,
  }) {
    final base = _positions.length ~/ 3;
    final p = src.positions;
    for (var i = 0; i < p.length; i += 3) {
      var lx = p[i];
      var ly = p[i + 1];
      var lz = p[i + 2];
      if (jag != null) {
        // Shove the vertex radially; on a unit sphere the position is its
        // own outward direction. Out for spikes, in for crevices: a craggy
        // silhouette off a smooth ball.
        final d = 1 + (jag.nextDouble() - 0.35) * jagAmount;
        lx *= d;
        ly *= d;
        lz *= d;
      }
      final v = transform.transform3(Vector3(lx, ly, lz));
      _positions
        ..add(v.x)
        ..add(v.y)
        ..add(v.z);
      _colors
        ..add(tone.x)
        ..add(tone.y)
        ..add(tone.z)
        ..add(1);
    }
    for (final index in src.indices) {
      _indices.add(base + index);
    }
  }

  Node toNode(String name) {
    // `MeshData.build` generates area-weighted normals from the merged
    // faces; props share no vertices, so each still shades as its own
    // smooth shape.
    final geometry = MeshGeometry.fromMeshData(
      MeshData.build(
        positions: Float32List.fromList(_positions),
        colors: Float32List.fromList(_colors),
        indices: _indices,
      ),
    );
    final material = PhysicallyBasedMaterial()
      ..baseColorFactor = Vector4(1, 1, 1, 1)
      ..vertexColorWeight = 1
      ..roughnessFactor = 1
      ..metallicFactor = 0;
    return Node(name: name)
      ..mesh = Mesh(geometry, material)
      ..shadowStatic = true;
  }
}

/// One base shape's CPU vertex data, read back once for baking.
class _Shape {
  _Shape(this.positions, this.indices);

  final Float32List positions;
  final List<int> indices;
}

_Shape _shape(Geometry geometry) {
  final data = geometry.extractMeshData();
  return _Shape(data.positions, data.indices ?? const []);
}
