// The pure half of the grass: field baking without a GPU context.
import 'dart:math' as math;

import 'package:combat_sample/features/world/vfx/grass_field.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a field bakes five vertices and nine indices per blade', () {
    final field = buildGrassField(100, radius: 10);
    expect(field.positions.length, 100 * GrassField.verticesPerBlade * 3);
    expect(field.normals.length, 100 * GrassField.verticesPerBlade * 3);
    expect(field.texCoords.length, 100 * GrassField.verticesPerBlade * 2);
    expect(field.colors.length, 100 * GrassField.verticesPerBlade * 4);
    expect(field.indices.length, 100 * GrassField.indicesPerBlade);
  });

  test('every blade stays inside the disc and above the ground', () {
    const radius = 10.0;
    final field = buildGrassField(500, radius: radius);
    for (var v = 0; v < field.positions.length ~/ 3; v++) {
      final x = field.positions[v * 3];
      final y = field.positions[v * 3 + 1];
      final z = field.positions[v * 3 + 2];
      // Static tip curvature can carry a blade just beyond its root radius.
      expect(math.sqrt(x * x + z * z), lessThanOrEqualTo(radius + 0.13));
      expect(y, inInclusiveRange(0, 0.95));
    }
  });

  test('indices are valid and sway weight runs from pinned root to tip', () {
    final field = buildGrassField(50, radius: 5);
    final vertexCount = field.positions.length ~/ 3;
    for (final index in field.indices) {
      expect(index, lessThan(vertexCount));
    }
    for (var v = 0; v < vertexCount; v++) {
      final uvY = field.texCoords[v * 2 + 1];
      final y = field.positions[v * 3 + 1];
      // uv.y is the sway seam: 0 at the free tip, 1 at the pinned root.
      expect(uvY, anyOf(0.0, closeTo(0.45, 1e-6), 1.0));
      expect(y == 0, uvY == 1.0);
    }
  });

  test('falloff thins the rim and leaves the core at full density', () {
    const radius = 20.0;
    const falloffStart = 12.0;
    final full = buildGrassField(4000, radius: radius);
    final faded = buildGrassField(
      4000,
      radius: radius,
      falloffStart: falloffStart,
    );
    expect(faded.bladeCount, lessThan(full.bladeCount));
    expect(faded.bladeCount, greaterThan(0));
    // Count root vertices (y == 0, uv.y == 1 -> two per blade) inside and
    // outside the falloff start. The larger outer annulus must still end up
    // sparser per unit area.
    var inner = 0;
    var outer = 0;
    for (var v = 0; v < faded.positions.length ~/ 3; v++) {
      if (faded.positions[v * 3 + 1] != 0) continue;
      final x = faded.positions[v * 3];
      final z = faded.positions[v * 3 + 2];
      final r = math.sqrt(x * x + z * z);
      if (r < falloffStart) {
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
    final a = buildGrassField(200, radius: 12);
    final b = buildGrassField(200, radius: 12);
    expect(a.positions, b.positions);
    expect(a.colors, b.colors);
  });
}
