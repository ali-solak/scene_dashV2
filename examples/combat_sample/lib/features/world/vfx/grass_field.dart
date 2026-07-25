// Pure blade-field baking: every blade is a small tapered ribbon in one set
// of flat vertex arrays, ready for MeshGeometry.fromArrays. Kept free of any
// geometry/GPU construction so it runs headless; the stage uploads the whole
// field as one mesh and one draw.
import 'dart:math' as math;
import 'dart:typed_data';

/// Flat vertex arrays for a baked field of tapered grass blades.
///
/// Each blade has two root vertices, two narrower mid vertices, and one tip.
/// Tint lives in [colors]; sway weight is encoded in uv.y (0 at the tip,
/// 1 at the pinned root) for the grass_sway.fmat vertex stage.
class GrassField {
  GrassField({
    required this.positions,
    required this.normals,
    required this.texCoords,
    required this.colors,
    required this.indices,
  });

  static const int verticesPerBlade = 5;
  static const int indicesPerBlade = 9;

  final Float32List positions;
  final Float32List normals;
  final Float32List texCoords;
  final Float32List colors;

  /// 32-bit because a dense field passes 65k vertices.
  final Uint32List indices;

  /// Blades that survived the density falloff (== attempts without falloff).
  int get bladeCount => positions.length ~/ (verticesPerBlade * 3);
}

/// Bakes up to [blades] tapered ribbons uniformly over a disc of [radius].
GrassField buildGrassField(
  int blades, {
  required double radius,
  double? falloffStart,
  int seed = 11,
}) {
  final rng = math.Random(seed);
  final positions = Float32List(blades * GrassField.verticesPerBlade * 3);
  final normals = Float32List(blades * GrassField.verticesPerBlade * 3);
  final texCoords = Float32List(blades * GrassField.verticesPerBlade * 2);
  final colors = Float32List(blades * GrassField.verticesPerBlade * 4);
  final indices = Uint32List(blades * GrassField.indicesPerBlade);
  var vertexCount = 0;
  var positionOffset = 0;
  var normalOffset = 0;
  var texCoordOffset = 0;
  var colorOffset = 0;
  var indexOffset = 0;

  void addVertex(
    double x,
    double y,
    double z,
    double u,
    double v,
    double red,
    double green,
    double blue,
  ) {
    positions[positionOffset++] = x;
    positions[positionOffset++] = y;
    positions[positionOffset++] = z;
    // Up normals keep two-sided ribbons lit consistently instead of making
    // random yaws alternate between bright and black.
    normals[normalOffset++] = 0;
    normals[normalOffset++] = 1;
    normals[normalOffset++] = 0;
    texCoords[texCoordOffset++] = u;
    texCoords[texCoordOffset++] = v;
    colors[colorOffset++] = red;
    colors[colorOffset++] = green;
    colors[colorOffset++] = blue;
    colors[colorOffset++] = 1;
    vertexCount++;
  }

  for (var blade = 0; blade < blades; blade++) {
    // sqrt keeps the disc uniform instead of center-heavy.
    final r = radius * math.sqrt(rng.nextDouble());
    final theta = rng.nextDouble() * math.pi * 2;
    final yaw = rng.nextDouble() * math.pi;
    final width = 0.045 + rng.nextDouble() * 0.05;
    final height = 0.45 + rng.nextDouble() * 0.5;
    final curve = (rng.nextDouble() - 0.5) * 0.24;
    final tint = rng.nextDouble();
    if (falloffStart != null && r > falloffStart) {
      // Smoothstep acceptance from 1 at falloffStart to 0 at the rim.
      final edge = ((r - falloffStart) / (radius - falloffStart)).clamp(
        0.0,
        1.0,
      );
      final keep = 1 - edge * edge * (3 - 2 * edge);
      if (rng.nextDouble() >= keep) continue;
    }

    final cx = math.cos(theta) * r;
    final cz = math.sin(theta) * r;
    final sideX = math.cos(yaw);
    final sideZ = math.sin(yaw);
    final halfRoot = width * 0.5;
    final halfMid = width * 0.28;
    final midShift = curve * 0.35;
    final midX = cx + sideX * midShift;
    final midZ = cz + sideZ * midShift;
    final tipX = cx + sideX * curve;
    final tipZ = cz + sideZ * curve;
    final red = 0.30 + 0.25 * tint;
    final green = 0.42 + 0.20 * tint;
    final blue = 0.13 + 0.10 * tint;
    final base = vertexCount;

    addVertex(
      cx - sideX * halfRoot,
      0,
      cz - sideZ * halfRoot,
      0,
      1,
      red,
      green,
      blue,
    );
    addVertex(
      cx + sideX * halfRoot,
      0,
      cz + sideZ * halfRoot,
      1,
      1,
      red,
      green,
      blue,
    );
    addVertex(
      midX - sideX * halfMid,
      height * 0.55,
      midZ - sideZ * halfMid,
      0.2,
      0.45,
      red,
      green,
      blue,
    );
    addVertex(
      midX + sideX * halfMid,
      height * 0.55,
      midZ + sideZ * halfMid,
      0.8,
      0.45,
      red,
      green,
      blue,
    );
    addVertex(tipX, height, tipZ, 0.5, 0, red, green, blue);

    indices[indexOffset++] = base;
    indices[indexOffset++] = base + 1;
    indices[indexOffset++] = base + 3;
    indices[indexOffset++] = base;
    indices[indexOffset++] = base + 3;
    indices[indexOffset++] = base + 2;
    indices[indexOffset++] = base + 2;
    indices[indexOffset++] = base + 3;
    indices[indexOffset++] = base + 4;
  }

  return GrassField(
    positions: Float32List.sublistView(positions, 0, positionOffset),
    normals: Float32List.sublistView(normals, 0, normalOffset),
    texCoords: Float32List.sublistView(texCoords, 0, texCoordOffset),
    colors: Float32List.sublistView(colors, 0, colorOffset),
    indices: Uint32List.sublistView(indices, 0, indexOffset),
  );
}
