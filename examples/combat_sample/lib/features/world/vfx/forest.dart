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

// Dimensions
const double _trunkHeight = 2.2;
const double _trunkBottomRadius = 0.3;
const double _trunkTopRadius = 0.2;
const double _coneHeight = 2.2;
const double _coneStep = 1.15;
const double _canopyBaseY = 1.6;
const List<double> _coneRadii = [2.0, 1.55, 1.1];
const double _rockRadius = 0.7;
const double _bushRadius = 0.55;

// Colors
final Vector3 _trunkTone = Vector3(0.36, 0.25, 0.16);
const List<(double, double, double)> _canopyTones = [
  (0.20, 0.34, 0.15),
  (0.16, 0.30, 0.18),
  (0.25, 0.38, 0.14),
];
final Vector3 _canopyTipTint = Vector3(1.35, 1.28, 0.95);
final Vector3 _rockTone = Vector3(0.45, 0.44, 0.42);
final Vector3 _mossTone = Vector3(0.28, 0.36, 0.17);
final Vector3 _bushTone = Vector3(0.18, 0.30, 0.14);
final Vector3 _cliffRockTone = Vector3(0.30, 0.30, 0.32);
final Vector3 _wetRockTone = Vector3(0.10, 0.12, 0.14);

const double _rockJag = 0.35;
const double _canopyJag = 0.12;
const double _bushJag = 0.2;
const double _baseShade = 0.72;
const double _mossFrom = 0.55;
const double _mossFull = 0.85;
const double _mossStrength = 0.75;
const double _toneJitter = 0.14;
const double _wetBand = 2.2;

typedef _Paint = Vector3 Function(
  double height,
  Vector3 normal,
  Vector3 position,
);

/// Bakes [placements] into one mesh.
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
          radialSegments: 7,
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
    final rng = math.Random(
      (placement.x * 73.1 + placement.z * 191.7).round() & 0x7fffffff,
    );
    final value = 1 + (rng.nextDouble() - 0.5) * 2 * _toneJitter;
    switch (placement.kind) {
      case PropKind.tree:
        mesher.add(
          trunk,
          base * Matrix4.translation(Vector3(0, _trunkHeight / 2, 0)),
          (height, normal, position) =>
              _trunkTone * (value * (_baseShade + (1 - _baseShade) * height)),
        );
        final t =
            _canopyTones[(placement.variantRoll * _canopyTones.length).floor() %
                _canopyTones.length];
        final canopy = Vector3(t.$1, t.$2, t.$3) * value;
        final tip = canopy.clone()..multiply(_canopyTipTint);
        for (var i = 0; i < _coneRadii.length; i++) {
          final underside = canopy * (_baseShade * (0.82 + 0.09 * i));
          mesher.add(
            cones[i],
            base *
                Matrix4.translation(
                  Vector3(0, _canopyBaseY + i * _coneStep + _coneHeight / 2, 0),
                ) *
                Matrix4.rotationY(rng.nextDouble() * math.pi),
            (height, normal, position) => _mix(underside, tip, height),
            jag: rng,
            jagAmount: _canopyJag,
          );
        }
      case PropKind.rock:
        final squash = 0.6 + 0.4 * placement.variantRoll;
        final tone = _rockTone * value;
        mesher.add(
          rock,
          base *
              Matrix4.translation(Vector3(0, _rockRadius * squash * 0.8, 0)) *
              Matrix4.diagonal3(Vector3(1, squash, 1)),
          (height, normal, position) =>
              _moss(tone * (_baseShade + (1 - _baseShade) * height), normal),
          jag: rng,
          jagAmount: _rockJag,
        );
      case PropKind.bush:
        final squash = 0.55 + 0.25 * placement.variantRoll;
        final tone = _bushTone * value;
        final tip = tone.clone()..multiply(_canopyTipTint);
        mesher.add(
          bush,
          base *
              Matrix4.translation(Vector3(0, _bushRadius * squash * 0.75, 0)) *
              Matrix4.diagonal3(Vector3(1.15, squash, 1.15)),
          (height, normal, position) => _mix(tone * _baseShade, tip, height),
          jag: rng,
          jagAmount: _bushJag,
        );
    }
  }
  return mesher.toNode('forest');
}

/// Builds the cliff rocks.
Node buildCliffRocks() {
  // Low detail rock shape.
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
    final tone = _cliffRockTone * (1 + (rng.nextDouble() - 0.5) * _toneJitter);
    mesher.add(
      rock,
      Matrix4.compose(
        Vector3(math.sin(theta) * radius, y, math.cos(theta) * radius),
        Quaternion.axisAngle(Vector3(0, 1, 0), rng.nextDouble() * 2 * math.pi),
        Vector3(size, size * squashY, size),
      ),
      (height, normal, position) => _mix(
        _wetRockTone,
        _moss(tone, normal),
        ((position.y - oceanLevel) / _wetBand).clamp(0.0, 1.0),
      ),
      jag: rng,
      jagAmount: cliffRockSpike,
    );
  }
  // Below the rim: nothing downhill of them receives a shadow.
  return mesher.toNode('cliff-rocks')
    ..shadowCastingMode = ShadowCastingMode.off;
}

Vector3 _mix(Vector3 a, Vector3 b, double t) => a + (b - a) * t;

Vector3 _moss(Vector3 tone, Vector3 normal) {
  final t = ((normal.y - _mossFrom) / (_mossFull - _mossFrom)).clamp(0.0, 1.0);
  return _mix(tone, _mossTone, t * t * _mossStrength);
}

/// Accumulates transformed, faceted, vertex-painted copies of base shapes
/// into one merged, lit mesh. Every triangle gets its own vertices, so the
/// generated normals are face normals and each facet catches the light.
class _Mesher {
  final _positions = <double>[];
  final _colors = <double>[];
  final _indices = <int>[];

  void add(
    _Shape src,
    Matrix4 transform,
    _Paint paint, {
    math.Random? jag,
    double jagAmount = 0,
  }) {
    final p = src.positions;
    var minY = double.infinity;
    var maxY = double.negativeInfinity;
    for (var i = 1; i < p.length; i += 3) {
      minY = math.min(minY, p[i]);
      maxY = math.max(maxY, p[i]);
    }
    final span = math.max(maxY - minY, 1e-6);
    final world = <Vector3>[];
    final heights = <double>[];
    for (var i = 0; i < p.length; i += 3) {
      var lx = p[i];
      var ly = p[i + 1];
      var lz = p[i + 2];
      heights.add((ly - minY) / span);
      if (jag != null) {
        // Shove the vertex radially; on a unit sphere the position is its
        // own outward direction. Out for spikes, in for crevices: a craggy
        // silhouette off a smooth ball.
        final d = 1 + (jag.nextDouble() - 0.35) * jagAmount;
        lx *= d;
        ly *= d;
        lz *= d;
      }
      world.add(transform.transform3(Vector3(lx, ly, lz)));
    }
    final indices = src.indices;
    for (var i = 0; i + 2 < indices.length; i += 3) {
      final a = world[indices[i]];
      final b = world[indices[i + 1]];
      final c = world[indices[i + 2]];
      final normal = (b - a).cross(c - a);
      if (normal.length2 < 1e-12) continue;
      normal.normalize();
      for (var k = 0; k < 3; k++) {
        final corner = indices[i + k];
        final v = world[corner];
        final color = paint(heights[corner], normal, v);
        _indices.add(_positions.length ~/ 3);
        _positions
          ..add(v.x)
          ..add(v.y)
          ..add(v.z);
        _colors
          ..add(color.x)
          ..add(color.y)
          ..add(color.z)
          ..add(1);
      }
    }
  }

  Node toNode(String name) {
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
