// The pure half of the grass: field baking without a GPU context.
import 'dart:math' as math;

import 'package:combat_sample/features/world/vfx/grass_field.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a field bakes three vertices and both windings per blade', () {
    final field = buildGrassField(98, radius: 10);
    expect(field.positions.length, 98 * GrassField.verticesPerBlade * 3);
    expect(field.normals.length, 98 * GrassField.verticesPerBlade * 3);
    expect(field.colors.length, 98 * GrassField.verticesPerBlade * 4);
    expect(field.indices.length, 98 * GrassField.indicesPerBlade);
  });

  test('every blade stays near the field disc and above the ground', () {
    const radius = 10.0;
    final field = buildGrassField(504, radius: radius);
    for (var v = 0; v < field.positions.length ~/ 3; v++) {
      final x = field.positions[v * 3];
      final y = field.positions[v * 3 + 1];
      final z = field.positions[v * 3 + 2];
      expect(math.sqrt(x * x + z * z), lessThanOrEqualTo(radius + 0.38));
      expect(y, inInclusiveRange(0, 0.82));
    }
  });

  test('indices are valid and roots stay distinguishable from tips', () {
    final field = buildGrassField(49, radius: 5);
    final vertexCount = field.positions.length ~/ 3;
    for (final index in field.indices) {
      expect(index, lessThan(vertexCount));
    }
    for (var blade = 0; blade < field.bladeCount; blade++) {
      final base = blade * GrassField.verticesPerBlade * 3;
      expect(field.positions[base + 1], 0);
      expect(field.positions[base + 4], 0);
      expect(field.positions[base + 7], greaterThan(0));
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
    final a = buildGrassField(196, radius: 12);
    final b = buildGrassField(196, radius: 12);
    expect(a.positions, b.positions);
    expect(a.colors, b.colors);
  });
}
