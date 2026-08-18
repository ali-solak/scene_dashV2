// The pure half of the grass: field placement without a GPU context.
import 'dart:math' as math;

import 'package:combat_sample/features/world/vfx/grass_field.dart';
import 'package:flutter_test/flutter_test.dart';

/// Column-major translation of blade [blade].
(double, double) _root(GrassField field, int blade) {
  final t = blade * GrassField.floatsPerTransform;
  return (field.transforms[t + 12], field.transforms[t + 14]);
}

/// Blade height: the Y column's Y component.
double _height(GrassField field, int blade) =>
    field.transforms[blade * GrassField.floatsPerTransform + 5];

void main() {
  test('a field emits one transform and one color per blade', () {
    final field = buildGrassField(98, radius: 10);
    expect(field.bladeCount, 98);
    expect(field.transforms.length, 98 * GrassField.floatsPerTransform);
    expect(field.colors.length, 98 * GrassField.floatsPerColor);
  });

  test('the shared blade carries three vertices and both windings', () {
    expect(GrassField.bladePositions.length, 3 * 3);
    expect(GrassField.bladeNormals.length, 3 * 3);
    expect(GrassField.bladeIndices, [0, 1, 2, 2, 1, 0]);
  });

  test('every blade stays near the field disc and stands above the ground', () {
    const radius = 10.0;
    final field = buildGrassField(504, radius: radius);
    for (var blade = 0; blade < field.bladeCount; blade++) {
      final (x, z) = _root(field, blade);
      expect(math.sqrt(x * x + z * z), lessThanOrEqualTo(radius + 0.38));
      expect(_height(field, blade), inInclusiveRange(0.42, 0.82));
      // Roots sit on the ground: the transform's Y translation.
      expect(field.transforms[blade * GrassField.floatsPerTransform + 13], 0);
    }
  });

  test('every transform keeps a positive determinant, so winding holds', () {
    final field = buildGrassField(49, radius: 5);
    for (var blade = 0; blade < field.bladeCount; blade++) {
      final t = blade * GrassField.floatsPerTransform;
      // det of the upper-left 3x3, columns (0,1,2).
      final a = field.transforms;
      final det =
          a[t] * (a[t + 5] * a[t + 10] - a[t + 6] * a[t + 9]) -
          a[t + 4] * (a[t + 1] * a[t + 10] - a[t + 2] * a[t + 9]) +
          a[t + 8] * (a[t + 1] * a[t + 6] - a[t + 2] * a[t + 5]);
      expect(det, greaterThan(0));
    }
  });

  test('falloff thins the rim and leaves the core at full density', () {
    const radius = 20.0;
    const falloffStart = 12.0;
    final full = buildGrassField(3997, radius: radius);
    final faded = buildGrassField(
      3997,
      radius: radius,
      falloffStart: falloffStart,
    );
    expect(faded.bladeCount, lessThan(full.bladeCount));
    expect(faded.bladeCount, greaterThan(0));

    var inner = 0;
    var outer = 0;
    for (var blade = 0; blade < faded.bladeCount; blade++) {
      final (x, z) = _root(faded, blade);
      if (math.sqrt(x * x + z * z) < falloffStart) {
        inner++;
      } else {
        outer++;
      }
    }
    final innerArea = math.pi * falloffStart * falloffStart;
    final outerArea = math.pi * (radius * radius - falloffStart * falloffStart);
    expect(outer / outerArea, lessThan(inner / innerArea * 0.6));
  });

  test('the same seed re-lays the same field', () {
    final a = buildGrassField(196, radius: 12);
    final b = buildGrassField(196, radius: 12);
    expect(a.transforms, b.transforms);
    expect(a.colors, b.colors);
  });
}
