import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';

/// A trivial [Component] used to exercise [SceneNode.component].
final class _ProbeComponent extends Component {
  _ProbeComponent(this.id);
  final int id;
}

final class _OtherComponent extends Component {}

void main() {
  group('SceneNode.component', () {
    test('returns the attached component of the requested type', () {
      final probe = _ProbeComponent(7);
      final node = Node()..addComponent(probe);
      final ref = SceneNode(node);

      final found = ref.component<_ProbeComponent>();
      expect(found, same(probe));
      expect(found!.id, 7);
    });

    test('returns null when no component of the type is attached', () {
      final ref = SceneNode(Node()..addComponent(_OtherComponent()));

      expect(ref.component<_ProbeComponent>(), isNull);
    });

    test('mirrors node.getComponent', () {
      final node = Node()..addComponent(_ProbeComponent(1));
      final ref = SceneNode(node);

      expect(ref.component<_ProbeComponent>(),
          same(node.getComponent<_ProbeComponent>()));
    });
  });
}
