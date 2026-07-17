import 'package:flutter_test/flutter_test.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  group('Gizmos staging', () {
    test('sphere writes packed floats into its color bucket', () {
      final gizmos = Gizmos()
        ..sphere(Vector3(1, 2, 3), 0.5, color: GizmoColor.red);

      final red = gizmos.buckets[GizmoColor.red.index];
      expect(red.sphereCount, 1);
      expect(red.spheres.sublist(0, 4), [1, 2, 3, 0.5]);
      expect(gizmos.buckets[GizmoColor.green.index].sphereCount, 0);
    });

    test('disabled makes every submission a no-op', () {
      final gizmos = Gizmos()
        ..enabled = false
        ..sphere(Vector3.zero(), 1)
        ..line(Vector3.zero(), Vector3(1, 0, 0))
        ..cuboid(Vector3.zero(), Vector3.all(1));

      for (final bucket in gizmos.buckets) {
        expect(bucket.sphereCount, 0);
        expect(bucket.lineCount, 0);
        expect(bucket.cuboidCount, 0);
      }
    });

    test('overflow drops and counts instead of growing', () {
      final gizmos = Gizmos(sphereCapacity: 2);
      for (var i = 0; i < 5; i++) {
        gizmos.sphere(Vector3.zero(), 1);
      }
      expect(gizmos.buckets[GizmoColor.green.index].sphereCount, 2);
      expect(gizmos.droppedThisFrame, 3);
    });

    test('ray normalizes direction and lands at origin + length', () {
      final gizmos = Gizmos()
        ..ray(Vector3(1, 0, 0), Vector3(0, 0, 5), 2, color: GizmoColor.blue);

      final blue = gizmos.buckets[GizmoColor.blue.index];
      expect(blue.lineCount, 1);
      expect(blue.lines.sublist(0, 6), [1, 0, 0, 1, 0, 2]);
    });

    test('clear resets all counts and the drop counter', () {
      final gizmos = Gizmos(sphereCapacity: 1)
        ..sphere(Vector3.zero(), 1)
        ..sphere(Vector3.zero(), 1) // dropped
        ..line(Vector3.zero(), Vector3(1, 0, 0));

      gizmos.clear();
      expect(gizmos.droppedThisFrame, 0);
      for (final bucket in gizmos.buckets) {
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
    // Several hundred shapes submitted in one frame — the volume a fully
    // instrumented scene produces. Staging must hold every submission
    // without dropping (capacities sized for it) and clear back to empty;
    // the GPU half of this path (pool writes riding 0.19's arena
    // transients, which lifted the old ~1MB per-frame transient ceiling)
    // is covered by the on-device smoke run.
    test('hundreds of shapes in one frame stage without drops', () {
      const perColor = 200;
      final gizmos = Gizmos(
        sphereCapacity: perColor,
        lineCapacity: perColor,
        cuboidCapacity: perColor,
      );

      for (var frame = 0; frame < 3; frame++) {
        gizmos.clear();
        for (final color in GizmoColor.values) {
          for (var i = 0; i < perColor; i++) {
            final d = i.toDouble();
            gizmos.sphere(Vector3(d, d + 1, d + 2), 0.5 + i * 0.01,
                color: color);
            gizmos.line(Vector3(d, 0, 0), Vector3(d, d + 1, 0), color: color);
            gizmos.cuboid(Vector3(0, d, 0), Vector3.all(0.25 + i * 0.01),
                color: color);
          }
        }

        expect(gizmos.droppedThisFrame, 0);
        for (final bucket in gizmos.buckets) {
          expect(bucket.sphereCount, perColor);
          expect(bucket.lineCount, perColor);
          expect(bucket.cuboidCount, perColor);
        }
      }

      // Spot-check the last slot's packed floats survived the volume.
      final last = gizmos.buckets[GizmoColor.yellow.index];
      final base = (perColor - 1) * 4;
      expect(last.spheres[base], (perColor - 1).toDouble());
      expect(last.spheres[base + 3], closeTo(0.5 + (perColor - 1) * 0.01, 1e-6));

      gizmos.clear();
      for (final bucket in gizmos.buckets) {
        expect(bucket.sphereCount, 0);
        expect(bucket.lineCount, 0);
        expect(bucket.cuboidCount, 0);
      }
    });
  });
}
