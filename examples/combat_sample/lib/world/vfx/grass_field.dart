// Pure card-field baking: every grass card as two crossed quads in flat
// vertex arrays, ready for MeshGeometry.fromArrays. Kept free of any
// geometry/GPU construction so it runs (and is tested) headless — the
// stage builds its field from this on the GPU side.
import 'dart:math' as math;
import 'dart:typed_data';

/// Flat vertex arrays for a baked card field (8 vertices, 12 indices per
/// card). Tint lives in [colors]; sway weight is encoded in uv.y (0 at the
/// tip, 1 at the pinned root) for the grass_sway.fmat vertex stage.
class GrassField {
  GrassField({
    required this.positions,
    required this.normals,
    required this.texCoords,
    required this.colors,
    required this.indices,
  });

  final Float32List positions;
  final Float32List normals;
  final Float32List texCoords;
  final Float32List colors;

  /// 32-bit: a dense field passes 65k vertices, and the engine packs
  /// 16-or-32-bit from the actual values at upload.
  final Uint32List indices;

  /// Cards that survived the density falloff (== attempts when there is
  /// none).
  int get cardCount => positions.length ~/ (8 * 3);
}

/// Bakes up to [cards] crossed-quad cards uniformly over a disc of [radius].
/// Deterministic for a given [seed] so density comparisons re-lay the same
/// field.
///
/// With [falloffStart] set, cards beyond it thin smoothly to zero at the rim
/// (full density inside), so the field dissolves under the treeline and fog
/// instead of ending at a hard edge; [cards] is then the full-density
/// attempt count and [GrassField.cardCount] reports the survivors.
GrassField buildGrassField(
  int cards, {
  required double radius,
  double? falloffStart,
  int seed = 11,
}) {
  final rng = math.Random(seed);
  final positions = <double>[];
  final normals = <double>[];
  final texCoords = <double>[];
  final colors = <double>[];
  final indices = <int>[];
  var v = 0;
  for (var c = 0; c < cards; c++) {
    // sqrt keeps the disc uniform instead of center-heavy.
    final r = radius * math.sqrt(rng.nextDouble());
    final theta = rng.nextDouble() * math.pi * 2;
    final yaw = rng.nextDouble() * math.pi;
    final w = 0.5 + rng.nextDouble() * 0.3;
    final h = 0.55 + rng.nextDouble() * 0.45;
    // Per-card tint: dry-grass green, varied.
    final t = rng.nextDouble();
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
    final tint = [0.30 + 0.25 * t, 0.42 + 0.20 * t, 0.13 + 0.10 * t, 1.0];
    for (var q = 0; q < 2; q++) {
      final a = yaw + q * math.pi / 2;
      final dx = math.cos(a) * w / 2;
      final dz = math.sin(a) * w / 2;
      // Four corners: top-left, top-right, bottom-right, bottom-left.
      final corners = [
        [cx - dx, h, cz - dz, 0.0, 0.0],
        [cx + dx, h, cz + dz, 1.0, 0.0],
        [cx + dx, 0.0, cz + dz, 1.0, 1.0],
        [cx - dx, 0.0, cz - dz, 0.0, 1.0],
      ];
      final base = v;
      for (final corner in corners) {
        positions.addAll([corner[0], corner[1], corner[2]]);
        // Up normals: cards shade like the ground they stand on instead of
        // flipping bright/dark as they yaw.
        normals.addAll(const [0, 1, 0]);
        texCoords.addAll([corner[3], corner[4]]);
        colors.addAll(tint);
        v++;
      }
      indices.addAll([base, base + 1, base + 2, base, base + 2, base + 3]);
    }
  }
  return GrassField(
    positions: Float32List.fromList(positions),
    normals: Float32List.fromList(normals),
    texCoords: Float32List.fromList(texCoords),
    colors: Float32List.fromList(colors),
    indices: Uint32List.fromList(indices),
  );
}

/// A cluster of tapered blade silhouettes as straight-alpha RGBA pixels:
/// opaque where grass is, transparent between blades (the material
/// alpha-tests at 0.5). Row 0 is uv.y == 0, the swaying tip end.
Uint8List bladePixels(int size, {int seed = 5}) {
  final pixels = Uint8List(size * size * 4);
  final rng = math.Random(seed);
  // Blades as triangles: wide at the bottom row, tapering to a tip near the
  // top; a slight lean so the silhouette is not a comb.
  final blades = [
    for (var b = 0; b < 7; b++)
      (
        root: (b + 0.5) / 7 + (rng.nextDouble() - 0.5) * 0.06,
        lean: (rng.nextDouble() - 0.5) * 0.25,
        width: 0.045 + rng.nextDouble() * 0.035,
        height: 0.75 + rng.nextDouble() * 0.25,
      ),
  ];
  for (var y = 0; y < size; y++) {
    // up = 0 at the roots (bottom row), 1 at the tips.
    final up = 1 - y / (size - 1);
    for (var x = 0; x < size; x++) {
      final u = x / (size - 1);
      var inside = false;
      for (final blade in blades) {
        if (up > blade.height) continue;
        final center = blade.root + blade.lean * up * up;
        final halfWidth = blade.width * (1 - up / blade.height);
        if ((u - center).abs() < halfWidth) {
          inside = true;
          break;
        }
      }
      final o = (y * size + x) * 4;
      if (inside) {
        // Darker toward the root; the per-card vertex tint does the rest.
        final shade = 0.55 + 0.45 * up;
        pixels[o] = (200 * shade).round();
        pixels[o + 1] = (230 * shade).round();
        pixels[o + 2] = (140 * shade).round();
        pixels[o + 3] = 255;
      }
    }
  }
  return pixels;
}
