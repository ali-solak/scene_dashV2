// The pure half of the grass: field baking and the blade texture pixels.
// Geometry/texture construction itself needs a GPU context and is
// exercised on device.
import 'dart:math' as math;

import 'package:combat_sample/world/vfx/grass_field.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a field bakes 8 vertices and 12 indices per card', () {
    final field = buildGrassField(100, radius: 10);
    expect(field.positions.length, 100 * 8 * 3);
    expect(field.normals.length, 100 * 8 * 3);
    expect(field.texCoords.length, 100 * 8 * 2);
    expect(field.colors.length, 100 * 8 * 4);
    expect(field.indices.length, 100 * 12);
  });

  test('every card stays inside the disc and above the ground', () {
    const radius = 10.0;
    final field = buildGrassField(500, radius: radius);
    for (var v = 0; v < field.positions.length ~/ 3; v++) {
      final x = field.positions[v * 3];
      final y = field.positions[v * 3 + 1];
      final z = field.positions[v * 3 + 2];
      // Card half-width never exceeds 0.4, so corners stay within +0.4.
      expect(math.sqrt(x * x + z * z), lessThanOrEqualTo(radius + 0.4));
      expect(y, inInclusiveRange(0, 1.0));
    }
  });

  test('indices reference valid vertices, tips carry uv.y 0 and roots 1', () {
    final field = buildGrassField(50, radius: 5);
    final vertexCount = field.positions.length ~/ 3;
    for (final index in field.indices) {
      expect(index, lessThan(vertexCount));
    }
    for (var v = 0; v < vertexCount; v++) {
      final uvY = field.texCoords[v * 2 + 1];
      final y = field.positions[v * 3 + 1];
      // uv.y is the sway weight seam: 0 at the free tip, 1 at the pinned root.
      expect(uvY, anyOf(0.0, 1.0));
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
    expect(faded.cardCount, lessThan(full.cardCount));
    expect(faded.cardCount, greaterThan(0));
    // Count root vertices (y == 0, uv.y == 1 → two per card per quad) inside
    // and outside the falloff start; the outer annulus is larger in area but
    // must end up sparser per unit area.
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

  test('the same seed re-lays the same field (density A/B comparisons)', () {
    final a = buildGrassField(200, radius: 12);
    final b = buildGrassField(200, radius: 12);
    expect(a.positions, b.positions);
    expect(a.colors, b.colors);
  });

  test('blade pixels are a binary mask: opaque blades on transparency', () {
    final pixels = bladePixels(64);
    var opaque = 0;
    for (var p = 0; p < 64 * 64; p++) {
      final alpha = pixels[p * 4 + 3];
      expect(alpha, anyOf(0, 255));
      if (alpha == 255) opaque++;
    }
    // Sanity: blades cover a meaningful share without flooding the card.
    expect(opaque / (64 * 64), inExclusiveRange(0.05, 0.6));
  });
}
