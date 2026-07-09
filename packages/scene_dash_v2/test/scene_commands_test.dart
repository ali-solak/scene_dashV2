import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';

final class _Marker extends Component {}

void main() {
  test('add/remove are deferred until flush', () {
    final root = Node();
    final commands = SceneCommands(root);
    final child = Node();

    commands.add(child);
    expect(child.parent, isNull, reason: 'deferred');
    expect(commands.isEmpty, isFalse);

    commands.flush();
    expect(child.parent, same(root));
    expect(commands.isEmpty, isTrue);

    commands.remove(child);
    expect(child.parent, same(root), reason: 'still deferred');
    commands.flush();
    expect(child.parent, isNull);
  });

  test('add honours an explicit parent', () {
    final root = Node();
    final parent = Node();
    root.add(parent);
    final commands = SceneCommands(root);
    final child = Node();

    commands
      ..add(child, parent: parent)
      ..flush();
    expect(child.parent, same(parent));
  });

  test('attach/detach components are deferred until flush', () {
    final root = Node();
    final commands = SceneCommands(root);
    final node = Node();
    final component = _Marker();

    commands.attach(node, component);
    expect(node.getComponent<_Marker>(), isNull, reason: 'deferred');
    commands.flush();
    expect(node.getComponent<_Marker>(), isNotNull);

    commands
      ..detach(node, component)
      ..flush();
    expect(node.getComponent<_Marker>(), isNull);
  });
}
