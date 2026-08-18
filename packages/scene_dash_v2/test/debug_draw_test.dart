import 'package:flutter_test/flutter_test.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  group('DebugDraw staging', () {
    test('sphere writes packed floats into its color bucket', () {
      final debugDraw = DebugDraw()
        ..sphere(Vector3(1, 2, 3), 0.5, color: DebugColor.red);

      final red = debugDraw.buckets[DebugColor.red.index];
      expect(red.sphereCount, 1);
      expect(red.spheres.sublist(0, 4), [1, 2, 3, 0.5]);
      expect(debugDraw.buckets[DebugColor.green.index].sphereCount, 0);
    });

    test('disabled makes every submission a no-op', () {
      final debugDraw = DebugDraw()
        ..enabled = false
        ..sphere(Vector3.zero(), 1)
        ..line(Vector3.zero(), Vector3(1, 0, 0))
        ..cuboid(Vector3.zero(), Vector3.all(1));

      for (final bucket in debugDraw.buckets) {
        expect(bucket.sphereCount, 0);
        expect(bucket.lineCount, 0);
        expect(bucket.cuboidCount, 0);
      }
    });

    test('overflow drops and counts instead of growing', () {
      final debugDraw = DebugDraw(sphereCapacity: 2);
      for (var i = 0; i < 5; i++) {
        debugDraw.sphere(Vector3.zero(), 1);
      }
      expect(debugDraw.buckets[DebugColor.green.index].sphereCount, 2);
      expect(debugDraw.droppedThisFrame, 3);
    });

    test('ray normalizes direction and lands at origin + length', () {
      final debugDraw = DebugDraw()
        ..ray(Vector3(1, 0, 0), Vector3(0, 0, 5), 2, color: DebugColor.blue);

      final blue = debugDraw.buckets[DebugColor.blue.index];
      expect(blue.lineCount, 1);
      expect(blue.lines.sublist(0, 6), [1, 0, 0, 1, 0, 2]);
    });

    test('clear resets all counts and the drop counter', () {
      final debugDraw = DebugDraw(sphereCapacity: 1)
        ..sphere(Vector3.zero(), 1)
        ..sphere(Vector3.zero(), 1) // dropped
        ..line(Vector3.zero(), Vector3(1, 0, 0));

      debugDraw.clear();
      expect(debugDraw.droppedThisFrame, 0);
      for (final bucket in debugDraw.buckets) {
        expect(bucket.sphereCount, 0);
        expect(bucket.lineCount, 0);
      }
    });
  });

  group('composeLineTransform', () {
    final out = Matrix4.zero();

    test('spans a to b with the requested thickness', () {
      composeLineTransform(out, 0, 0, 0, 4, 0, 0, 0.1);
      final s = out.storage;
      // Forward column carries the full length along +X.
      expect(s[8], closeTo(4, 1e-6));
      expect(s[9], closeTo(0, 1e-6));
      expect(s[10], closeTo(0, 1e-6));
      // Cross-section columns have thickness magnitude.
      expect(Vector3(s[0], s[1], s[2]).length, closeTo(0.1, 1e-6));
      expect(Vector3(s[4], s[5], s[6]).length, closeTo(0.1, 1e-6));
      // Translation sits at the midpoint.
      expect(s[12], closeTo(2, 1e-6));
      expect(s[13], closeTo(0, 1e-6));
      expect(s[14], closeTo(0, 1e-6));
    });

    test('unit-cube corners map onto the segment endpoints', () {
      composeLineTransform(out, 1, 2, 3, -2, 5, 7, 0.05);
      // The unit cube spans -0.5..0.5 along its local Z (forward) axis.
      final start = out.transform3(Vector3(0, 0, -0.5));
      final end = out.transform3(Vector3(0, 0, 0.5));
      expect(start.x, closeTo(1, 1e-6));
      expect(start.y, closeTo(2, 1e-6));
      expect(start.z, closeTo(3, 1e-6));
      expect(end.x, closeTo(-2, 1e-6));
      expect(end.y, closeTo(5, 1e-6));
      expect(end.z, closeTo(7, 1e-6));
    });

    test('vertical lines fall back to a valid basis', () {
      composeLineTransform(out, 0, 0, 0, 0, 3, 0, 0.1);
      final s = out.storage;
      expect(Vector3(s[8], s[9], s[10]).length, closeTo(3, 1e-6));
      expect(Vector3(s[0], s[1], s[2]).length, closeTo(0.1, 1e-6));
      expect(Vector3(s[4], s[5], s[6]).length, closeTo(0.1, 1e-6));
      // Basis stays orthogonal.
      expect(
        Vector3(s[0], s[1], s[2]).dot(Vector3(s[8], s[9], s[10])),
        closeTo(0, 1e-6),
      );
    });

    test('a degenerate segment collapses to zero scale', () {
      composeLineTransform(out, 1, 1, 1, 1, 1, 1, 0.1);
      final s = out.storage;
      expect(s[0], 0);
      expect(s[5], 0);
      expect(s[10], 0);
      expect(s[15], 1);
    });
  });

  group('heavy frame', () {
    // Staging holds a heavily instrumented frame without dropping shapes.
    test('hundreds of shapes in one frame stage without drops', () {
      const perColor = 200;
      final debugDraw = DebugDraw(
        sphereCapacity: perColor,
        lineCapacity: perColor,
        cuboidCapacity: perColor,
      );

      for (var frame = 0; frame < 3; frame++) {
        debugDraw.clear();
        for (final color in DebugColor.values) {
          for (var i = 0; i < perColor; i++) {
            final d = i.toDouble();
            debugDraw.sphere(
              Vector3(d, d + 1, d + 2),
              0.5 + i * 0.01,
              color: color,
            );
            debugDraw.line(Vector3(d, 0, 0), Vector3(d, d + 1, 0), color: color);
            debugDraw.cuboid(
              Vector3(0, d, 0),
              Vector3.all(0.25 + i * 0.01),
              color: color,
            );
          }
        }

        expect(debugDraw.droppedThisFrame, 0);
        for (final bucket in debugDraw.buckets) {
          expect(bucket.sphereCount, perColor);
          expect(bucket.lineCount, perColor);
          expect(bucket.cuboidCount, perColor);
        }
      }

      // Spot-check the last slot's packed floats survived the volume.
      final last = debugDraw.buckets[DebugColor.yellow.index];
      final base = (perColor - 1) * 4;
      expect(last.spheres[base], (perColor - 1).toDouble());
      expect(
        last.spheres[base + 3],
        closeTo(0.5 + (perColor - 1) * 0.01, 1e-6),
      );

      debugDraw.clear();
      for (final bucket in debugDraw.buckets) {
        expect(bucket.sphereCount, 0);
        expect(bucket.lineCount, 0);
        expect(bucket.cuboidCount, 0);
      }
    });
  });
}
