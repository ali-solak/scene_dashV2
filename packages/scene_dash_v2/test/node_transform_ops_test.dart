import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  test('setLocalTRS builds translate-then-scale without allocating', () {
    final node = Node();
    final before = node.localTransform;
    node.setLocalTRS(1, 2, 3, 2, 4, 8);

    expect(identical(node.localTransform, before), isTrue,
        reason: 'mutates the existing matrix in place');
    final s = node.localTransform.storage;
    expect(s[12], 1);
    expect(s[13], 2);
    expect(s[14], 3);
    expect(s[0], 2);
    expect(s[5], 4);
    expect(s[10], 8);
  });

  test('setLocalUniform applies one scale on all axes', () {
    final node = Node()..setLocalUniform(0, 5, 0, 3);
    final s = node.localTransform.storage;
    expect(s[13], 5);
    expect(s[0], 3);
    expect(s[5], 3);
    expect(s[10], 3);
  });

  test('setLocalTRS overwrites any prior transform', () {
    final node = Node()
      ..localTransform = Matrix4.rotationY(1.3)
      ..setLocalTRS(7, 0, 0, 1, 1, 1);
    final expected = Matrix4.translation(Vector3(7, 0, 0));
    expect(node.localTransform, expected);
  });

  test('globalTranslationInto composes parent chains, no allocation', () {
    final parent = Node()
      ..localTransform = Matrix4.translation(Vector3(10, 0, 0));
    final child = Node()
      ..localTransform = Matrix4.translation(Vector3(0, 2, 0));
    parent.add(child);

    final out = Vector3.zero();
    child.globalTranslationInto(out);
    expect(out, Vector3(10, 2, 0));
  });

  test('localTranslationInto reads the local matrix', () {
    final node = Node()..setLocalTRS(4, 5, 6, 2, 2, 2);
    final out = Vector3.zero();
    node.localTranslationInto(out);
    expect(out, Vector3(4, 5, 6));
  });
}
