/// The pancake fix (NOTES.md B1): `harmoniseRotationHemispheres` makes
/// cross-clip blending take the short slerp path. Above all it must NOT
/// change any pose; a bad sign flip silently breaks every animation.
library;

// ignore_for_file: implementation_imports
import 'package:combat_sample/anim/hemisphere.dart';
import 'package:flutter_scene/scene.dart' show Animation;
import 'package:flutter_scene/src/animation.dart'
    show
        AnimationChannel,
        AnimationProperty,
        BindKey,
        PropertyResolver,
        RotationTimelineResolver;
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' show Quaternion, Vector3;

/// A one-channel animation rotating [node] through [keys].
Animation clipOf(String name, String node, List<Quaternion> keys) {
  return Animation(
    name: name,
    channels: [
      AnimationChannel(
        bindTarget: BindKey(
          nodeName: node,
          property: AnimationProperty.rotation,
        ),
        resolver: PropertyResolver.makeRotationTimeline([
          for (var i = 0; i < keys.length; i++) i * 0.1,
        ], keys),
      ),
    ],
  );
}

/// The live keyframe quaternions of a one-channel clip.
List<Quaternion> keysOf(Animation clip) =>
    (clip.channels.first.resolver as RotationTimelineResolver).values;

double dot(Quaternion a, Quaternion b) =>
    a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w;

Quaternion negated(Quaternion q) => Quaternion(-q.x, -q.y, -q.z, -q.w);

/// Where [q] sends a probe vector: the pose, independent of sign.
Vector3 posed(Quaternion q) => q.rotated(Vector3(1, 2, 3));

void main() {
  test('clips holding antipodal quaternions end up in one hemisphere', () {
    final upright = Quaternion.axisAngle(Vector3(0, 1, 0), 0.4)..normalize();
    // The same orientation, written the other way round: exactly what an
    // exporter is free to emit and what sends slerp the long way.
    final flipped = negated(upright);

    final a = clipOf('idle', 'spine', [upright.clone()]);
    final b = clipOf('swing', 'spine', [flipped.clone()]);
    expect(
      dot(keysOf(a).first, keysOf(b).first),
      lessThan(0),
      reason: 'the setup really is antipodal',
    );

    harmoniseRotationHemispheres([a, b]);

    expect(
      dot(keysOf(a).first, keysOf(b).first),
      greaterThanOrEqualTo(0),
      reason: 'slerp between these now takes the short path',
    );
  });

  test('alignment never changes a pose', () {
    final keys = [
      Quaternion.axisAngle(Vector3(0, 1, 0), 0.3)..normalize(),
      negated(Quaternion.axisAngle(Vector3(1, 0, 0), 1.9)..normalize()),
      Quaternion.axisAngle(Vector3(0, 0, 1), 2.7)..normalize(),
    ];
    final before = [for (final key in keys) posed(key)];

    final clip = clipOf('swing', 'spine', [for (final k in keys) k.clone()]);
    harmoniseRotationHemispheres([clip]);

    final after = keysOf(clip);
    for (var i = 0; i < before.length; i++) {
      final posedAfter = posed(after[i]);
      expect(posedAfter.x, closeTo(before[i].x, 1e-9));
      expect(posedAfter.y, closeTo(before[i].y, 1e-9));
      expect(posedAfter.z, closeTo(before[i].z, 1e-9));
    }
  });

  test('successive keyframes within a clip stay short-path to each other', () {
    // A joint winding steadily past 180°, written with signs that flip
    // partway: the intra-clip case.
    final keys = <Quaternion>[];
    for (var i = 0; i < 8; i++) {
      final q = Quaternion.axisAngle(Vector3(0, 1, 0), i * 0.5)..normalize();
      keys.add(i.isOdd ? negated(q) : q);
    }
    final clip = clipOf('spin', 'spine', keys);

    harmoniseRotationHemispheres([clip]);

    final aligned = keysOf(clip);
    for (var i = 1; i < aligned.length; i++) {
      expect(
        dot(aligned[i - 1], aligned[i]),
        greaterThanOrEqualTo(0),
        reason: 'keyframe $i turns the short way from ${i - 1}',
      );
    }
  });

  test('the anchor does NOT drift as clips are aligned in turn', () {
    // The bug this pins: the anchor used to be overwritten by each clip's
    // first keyframe, so C aligned to B instead of A and could come out
    // antipodal to A. Every clip must align to the FIRST clip.
    final a = Quaternion.axisAngle(Vector3(0, 1, 0), 0.0)..normalize();
    final b = Quaternion.axisAngle(Vector3(0, 1, 0), 2.6)..normalize();
    final c = Quaternion.axisAngle(Vector3(0, 1, 0), 5.2)..normalize();

    final clipA = clipOf('idle', 'spine', [a.clone()]);
    final clipB = clipOf('walk', 'spine', [b.clone()]);
    final clipC = clipOf('swing', 'spine', [c.clone()]);

    harmoniseRotationHemispheres([clipA, clipB, clipC]);

    // Everything is measured against the first clip, which is what the
    // blender will actually be interpolating from and to.
    final anchor = keysOf(clipA).first;
    expect(dot(anchor, keysOf(clipB).first), greaterThanOrEqualTo(0));
    expect(
      dot(anchor, keysOf(clipC).first),
      greaterThanOrEqualTo(0),
      reason: 'the third clip is aligned to the first, not to the second',
    );
  });

  test('a joint no clip mentions is simply left alone', () {
    final clip = clipOf('idle', 'spine', [Quaternion.identity()]);
    // Nothing to align against, nothing to do, and no crash.
    harmoniseRotationHemispheres([clip]);
    expect(keysOf(clip), hasLength(1));
  });
}
