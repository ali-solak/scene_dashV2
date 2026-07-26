// Pure blade-field baking: real tapered blades grouped into small tufts in
// flat vertex arrays, ready for MeshGeometry.fromArrays. The stage uploads
// the whole field as one mesh and one draw.
import 'dart:math' as math;
import 'dart:typed_data';

/// Vertex data for tapered grass blades.
class GrassField {
  GrassField({
    required this.positions,
    required this.normals,
    required this.colors,
    required this.indices,
  });

  static const int verticesPerBlade = 3;
  static const int indicesPerBlade = 6;

  final Float32List positions;
  final Float32List normals;
  final Float32List colors;
  final Uint32List indices;

  /// Blades that survived the tuft-level density falloff.
  int get bladeCount => positions.length ~/ (verticesPerBlade * 3);
}

/// Bakes grass blade tufts over a disc.
GrassField buildGrassField(
  int blades, {
  required double radius,
  double? falloffStart,
  int seed = 11,
}) {
  const bladesPerTuft = 7;
  // Tuft size.
  const tuftRadius = 0.24;
  final rng = math.Random(seed);
  final positions = Float32List(blades * GrassField.verticesPerBlade * 3);
  final normals = Float32List(blades * GrassField.verticesPerBlade * 3);
  final colors = Float32List(blades * GrassField.verticesPerBlade * 4);
  final indices = Uint32List(blades * GrassField.indicesPerBlade);
  var vertexCount = 0;
  var positionOffset = 0;
  var normalOffset = 0;
  var colorOffset = 0;
  var indexOffset = 0;

  void addVertex(
    double x,
    double y,
    double z,
    double red,
    double green,
    double blue,
  ) {
    positions[positionOffset++] = x;
    positions[positionOffset++] = y;
    positions[positionOffset++] = z;
    // Use even ground lighting.
    normals[normalOffset++] = 0;
    normals[normalOffset++] = 1;
    normals[normalOffset++] = 0;
    colors[colorOffset++] = red;
    colors[colorOffset++] = green;
    colors[colorOffset++] = blue;
    colors[colorOffset++] = 1;
    vertexCount++;
  }

  for (var tuft = 0; tuft < blades; tuft += bladesPerTuft) {
    // Uniform tuft distribution.
    final r = radius * math.sqrt(rng.nextDouble());
    final theta = rng.nextDouble() * math.pi * 2;
    if (falloffStart != null && r > falloffStart) {
      final edge = ((r - falloffStart) / (radius - falloffStart)).clamp(
        0.0,
        1.0,
      );
      final keep = 1 - edge * edge * (3 - 2 * edge);
      if (rng.nextDouble() >= keep) continue;
    }

    final tuftX = math.cos(theta) * r;
    final tuftZ = math.sin(theta) * r;
    final tuftTint = rng.nextDouble();
    final end = math.min(tuft + bladesPerTuft, blades);
    for (var blade = tuft; blade < end; blade++) {
      final localRadius = tuftRadius * math.sqrt(rng.nextDouble());
      final localTheta = rng.nextDouble() * math.pi * 2;
      final cx = tuftX + math.cos(localTheta) * localRadius;
      final cz = tuftZ + math.sin(localTheta) * localRadius;
      final yaw = rng.nextDouble() * math.pi;
      final width = 0.035 + rng.nextDouble() * 0.04;
      final height = 0.42 + rng.nextDouble() * 0.40;
      final curve = (rng.nextDouble() - 0.5) * 0.18;
      final tint = (tuftTint * 0.7 + rng.nextDouble() * 0.3).clamp(0.0, 1.0);
      final sideX = math.cos(yaw);
      final sideZ = math.sin(yaw);
      final halfRoot = width * 0.5;
      final red = 0.30 + 0.25 * tint;
      final green = 0.42 + 0.20 * tint;
      final blue = 0.13 + 0.10 * tint;
      final base = vertexCount;

      addVertex(
        cx - sideX * halfRoot,
        0,
        cz - sideZ * halfRoot,
        red,
        green,
        blue,
      );
      addVertex(
        cx + sideX * halfRoot,
        0,
        cz + sideZ * halfRoot,
        red,
        green,
        blue,
      );
      addVertex(
        cx + sideX * curve,
        height,
        cz + sideZ * curve,
        red,
        green,
        blue,
      );

      // Front and back windings: material-less shadow passes otherwise cull
      // roughly half of the randomly oriented blades.
      indices[indexOffset++] = base;
      indices[indexOffset++] = base + 1;
      indices[indexOffset++] = base + 2;
      indices[indexOffset++] = base + 2;
      indices[indexOffset++] = base + 1;
      indices[indexOffset++] = base;
    }
  }

  return GrassField(
    positions: Float32List.sublistView(positions, 0, positionOffset),
    normals: Float32List.sublistView(normals, 0, normalOffset),
    colors: Float32List.sublistView(colors, 0, colorOffset),
    indices: Uint32List.sublistView(indices, 0, indexOffset),
  );
}
