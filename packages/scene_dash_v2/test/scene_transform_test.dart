import 'package:flutter_test/flutter_test.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';
import 'package:vector_math/vector_math.dart' show Matrix4, Quaternion, Vector3;

void _expectVec3Close(Vector3 actual, Vector3 expected, {double tol = 1e-9}) {
  expect(actual.x, closeTo(expected.x, tol), reason: 'x');
  expect(actual.y, closeTo(expected.y, tol), reason: 'y');
  expect(actual.z, closeTo(expected.z, tol), reason: 'z');
}

void main() {
  group('translation', () {
    test('setTranslation / setTranslationFrom set absolute position', () {
      final t = SceneTransform.zero()..setTranslation(1, 2, 3);
      _expectVec3Close(t.translation, Vector3(1, 2, 3));
      t.setTranslationFrom(Vector3(4, 5, 6));
      _expectVec3Close(t.translation, Vector3(4, 5, 6));
    });

    test('translate / translateBy are relative', () {
      final t = SceneTransform(1, 1, 1)
        ..translate(1, 2, 3)
        ..translateBy(Vector3(1, 1, 1));
      _expectVec3Close(t.translation, Vector3(3, 4, 5));
    });

    test('setTranslationFrom copies, does not alias', () {
      final source = Vector3(1, 2, 3);
      final t = SceneTransform.zero()..setTranslationFrom(source);
      source.x = 99;
      expect(t.translation.x, 1);
    });
  });

  group('scale', () {
    test('setScale / setUniformScale / setScaleFrom', () {
      final t = SceneTransform.zero()..setScale(2, 3, 4);
      _expectVec3Close(t.scale, Vector3(2, 3, 4));
      t.setUniformScale(5);
      _expectVec3Close(t.scale, Vector3(5, 5, 5));
      t.setScaleFrom(Vector3(6, 7, 8));
      _expectVec3Close(t.scale, Vector3(6, 7, 8));
    });
  });

  group('rotation', () {
    test('setRotationX/Y/Z match axis-angle', () {
      const a = 0.7;
      for (final (set, axis) in [
        (SceneTransform.zero()..setRotationX(a), Vector3(1, 0, 0)),
        (SceneTransform.zero()..setRotationY(a), Vector3(0, 1, 0)),
        (SceneTransform.zero()..setRotationZ(a), Vector3(0, 0, 1)),
      ]) {
        final expected = Quaternion.axisAngle(axis, a);
        // Compare effect on a probe vector (quaternion sign is ambiguous).
        _expectVec3Close(
          set.rotation.rotated(Vector3(1, 2, 3)),
          expected.rotated(Vector3(1, 2, 3)),
        );
      }
    });

    test('setRotationEuler matches vector_math setEuler(yaw, pitch, roll)', () {
      const pitchX = 0.3, yawY = 0.5, rollZ = 0.2;
      final t = SceneTransform.zero()..setRotationEuler(pitchX, yawY, rollZ);
      final expected = Quaternion.euler(yawY, pitchX, rollZ);
      _expectVec3Close(
        t.rotation.rotated(Vector3(1, 0, 0)),
        expected.rotated(Vector3(1, 0, 0)),
      );
    });

    test('rotateY compounds to setRotationY of the sum', () {
      final incremental = SceneTransform.zero()
        ..rotateY(0.4)
        ..rotateY(0.4);
      final absolute = SceneTransform.zero()..setRotationY(0.8);
      _expectVec3Close(
        incremental.rotation.rotated(Vector3(1, 0, 0)),
        absolute.rotation.rotated(Vector3(1, 0, 0)),
      );
    });

    test('rotation stays normalized after many compositions', () {
      final t = SceneTransform.zero();
      for (var i = 0; i < 1000; i++) {
        t.rotateZ(0.1);
      }
      expect(t.rotation.length, closeTo(1, 1e-6));
    });

    test('setRotationIdentity resets orientation', () {
      final t = SceneTransform.zero()
        ..setRotationY(1.0)
        ..setRotationIdentity();
      _expectVec3Close(t.rotation.rotated(Vector3(1, 2, 3)), Vector3(1, 2, 3));
    });
  });

  group('copy & reset', () {
    test('setFrom copies all three channels', () {
      final source = SceneTransform.trs(
        translation: Vector3(1, 2, 3),
        rotation: Quaternion.axisAngle(Vector3(0, 1, 0), 0.5),
        scale: Vector3(2, 2, 2),
      );
      final t = SceneTransform.zero()..setFrom(source);
      _expectVec3Close(t.translation, source.translation);
      _expectVec3Close(t.scale, source.scale);
      _expectVec3Close(
        t.rotation.rotated(Vector3(1, 0, 0)),
        source.rotation.rotated(Vector3(1, 0, 0)),
      );
      // Independent copy.
      source.translation.x = 99;
      expect(t.translation.x, 1);
    });

    test('setIdentity resets translation, rotation and scale', () {
      final t = SceneTransform(5, 6, 7)
        ..setScale(2, 3, 4)
        ..setRotationY(1)
        ..setIdentity();
      _expectVec3Close(t.translation, Vector3.zero());
      _expectVec3Close(t.scale, Vector3.all(1));
      _expectVec3Close(t.rotation.rotated(Vector3(1, 2, 3)), Vector3(1, 2, 3));
    });
  });

  group('matrix interop', () {
    test('toMatrix(out) avoids allocation and matches a fresh matrix', () {
      final t = SceneTransform.trs(
        translation: Vector3(1, 2, 3),
        rotation: Quaternion.axisAngle(Vector3(0, 0, 1), 0.25),
        scale: Vector3(2, 3, 4),
      );
      final out = Matrix4.zero();
      final returned = t.toMatrix(out);
      expect(identical(returned, out), isTrue);
      final fresh = t.toMatrix();
      for (var i = 0; i < 16; i++) {
        expect(out[i], closeTo(fresh[i], 1e-12), reason: 'm[$i]');
      }
    });

    test('setFromMatrix round-trips a pure TRS matrix', () {
      final original = SceneTransform.trs(
        translation: Vector3(1, 2, 3),
        rotation: Quaternion.axisAngle(Vector3(0, 1, 0), 0.6),
        scale: Vector3(2, 2, 2),
      );
      final restored = SceneTransform.zero()
        ..setFromMatrix(original.toMatrix());
      _expectVec3Close(restored.translation, original.translation, tol: 1e-6);
      _expectVec3Close(restored.scale, original.scale, tol: 1e-6);
      _expectVec3Close(
        restored.rotation.rotated(Vector3(1, 0, 0)),
        original.rotation.rotated(Vector3(1, 0, 0)),
        tol: 1e-6,
      );
    });
  });

  group('lookAt', () {
    test('points local -Z at the target', () {
      final t = SceneTransform.fromVector(Vector3(0, 0, 0))
        ..lookAt(Vector3(1, 0, 0));
      // Local forward (-Z) should now point toward +X.
      final forward = t.rotation.rotated(Vector3(0, 0, -1));
      _expectVec3Close(forward, Vector3(1, 0, 0), tol: 1e-6);
    });

    test('keeps up roughly +Y', () {
      final t = SceneTransform.zero()..lookAt(Vector3(0, 0, -5));
      final up = t.rotation.rotated(Vector3(0, 1, 0));
      _expectVec3Close(up, Vector3(0, 1, 0), tol: 1e-6);
    });

    test('leaves rotation unchanged when target == position', () {
      final t = SceneTransform.zero()
        ..setRotationY(1.0)
        ..lookAt(Vector3.zero());
      final expected = SceneTransform.zero()..setRotationY(1.0);
      _expectVec3Close(
        t.rotation.rotated(Vector3(1, 0, 0)),
        expected.rotation.rotated(Vector3(1, 0, 0)),
      );
    });

    test('stays well-defined when look direction is parallel to up', () {
      // Looking straight down: forward == -up.
      final t = SceneTransform.zero()..lookAt(Vector3(0, -1, 0));
      final forward = t.rotation.rotated(Vector3(0, 0, -1));
      _expectVec3Close(forward, Vector3(0, -1, 0), tol: 1e-6);
      // Result must be a valid (finite, unit) quaternion.
      expect(t.rotation.length, closeTo(1, 1e-6));
      expect(
        forward.x.isFinite && forward.y.isFinite && forward.z.isFinite,
        isTrue,
      );
    });
  });
}
