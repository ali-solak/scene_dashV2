// Pure blade-field placement: real tapered blades grouped into small tufts,
// emitted as instance transforms over one shared blade geometry. The stage
// uploads three vertices once and one 80-byte instance per blade.
import 'dart:math' as math;
import 'dart:typed_data';

/// Instance data for tapered grass blades.
class GrassField {
  GrassField({required this.transforms, required this.colors});

  /// Column-major `Matrix4` storage, one per blade.
  static const int floatsPerTransform = 16;
  static const int floatsPerColor = 4;

  /// The shared blade: a triangle standing on the XZ plane, one unit tall and
  /// one unit wide, which each instance transform stretches into place.
  static const List<double> bladePositions = [
    -0.5, 0, 0, //
    0.5, 0, 0, //
    0, 1, 0, //
  ];

  /// Flat, so the field lights evenly; the material re-flattens the world
  /// normal after the instance transform shears it.
  static const List<double> bladeNormals = [
    0, 1, 0, //
    0, 1, 0, //
    0, 1, 0, //
  ];

  /// Both windings, so material-less shadow passes do not cull roughly half
  /// the randomly oriented blades. Shared, so it costs six indices total.
  static const List<int> bladeIndices = [0, 1, 2, 2, 1, 0];

  final Float32List transforms;
  final Float32List colors;

  /// Blades that survived the tuft-level density falloff.
  int get bladeCount => transforms.length ~/ floatsPerTransform;
}

/// Places grass blade tufts over a disc.
GrassField buildGrassField(
  int blades, {
  required double radius,
  double? falloffStart,
  int seed = 11,
  double widthScale = 1.0,
}) {
  const bladesPerTuft = 7;
  // Tuft size.
  const tuftRadius = 0.24;
  final rng = math.Random(seed);
  final transforms = Float32List(blades * GrassField.floatsPerTransform);
  final colors = Float32List(blades * GrassField.floatsPerColor);
  var transformOffset = 0;
  var colorOffset = 0;

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
      final width = (0.035 + rng.nextDouble() * 0.04) * widthScale;
      final height = 0.42 + rng.nextDouble() * 0.40;
      final curve = (rng.nextDouble() - 0.5) * 0.18;
      final tint = (tuftTint * 0.7 + rng.nextDouble() * 0.3).clamp(0.0, 1.0);
      final sideX = math.cos(yaw);
      final sideZ = math.sin(yaw);

      // Columns: the root edge along `side`, the tip lifted by `height` and
      // leaned by `curve`, and a perpendicular third so the basis stays
      // right-handed (a negative determinant would flip the winding).
      final t = transformOffset;
      transforms[t] = sideX * width;
      transforms[t + 2] = sideZ * width;
      transforms[t + 4] = sideX * curve;
      transforms[t + 5] = height;
      transforms[t + 6] = sideZ * curve;
      transforms[t + 8] = -sideZ * width;
      transforms[t + 10] = sideX * width;
      transforms[t + 12] = cx;
      transforms[t + 14] = cz;
      transforms[t + 15] = 1;
      transformOffset += GrassField.floatsPerTransform;

      colors[colorOffset++] = 0.30 + 0.25 * tint;
      colors[colorOffset++] = 0.42 + 0.20 * tint;
      colors[colorOffset++] = 0.13 + 0.10 * tint;
      colors[colorOffset++] = 1;
    }
  }

  return GrassField(
    transforms: Float32List.sublistView(transforms, 0, transformOffset),
    colors: Float32List.sublistView(colors, 0, colorOffset),
  );
}
