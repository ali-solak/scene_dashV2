import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';

/// Test component.
final class _ProbeComponent extends Component {
  _ProbeComponent(this.id);
  final int id;
}

final class _OtherComponent extends Component {}

void main() {
  group('NodeRef.component', () {
    test('returns the attached component of the requested type', () {
      final probe = _ProbeComponent(7);
      final node = Node()..addComponent(probe);
      final ref = NodeRef(node);

      final found = ref.component<_ProbeComponent>();
      expect(found, same(probe));
      expect(found!.id, 7);
    });

    test('returns null when no component of the type is attached', () {
      final ref = NodeRef(Node()..addComponent(_OtherComponent()));

      expect(ref.component<_ProbeComponent>(), isNull);
    });

    test('mirrors node.getComponent', () {
      final node = Node()..addComponent(_ProbeComponent(1));
      final ref = NodeRef(node);

      expect(
        ref.component<_ProbeComponent>(),
        same(node.getComponent<_ProbeComponent>()),
      );
    });
  });
}
