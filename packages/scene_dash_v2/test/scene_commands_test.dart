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

  test('a failed flush discards its consumed prefix without replay', () {
    final root = Node();
    final commands = SceneCommands(root);
    final first = Node();
    final after = Node();
    final attached = _Marker();
    final owner = Node()..addComponent(attached);

    commands
      ..add(first)
      // Reattaching an attached component is a reliable throwing operation.
      ..attach(Node(), attached)
      ..add(after);

    expect(commands.flush, throwsException);
    expect(first.parent, same(root), reason: 'the successful prefix applied');
    expect(attached.node, same(owner), reason: 'the throwing op was discarded');
    expect(after.parent, isNull, reason: 'the untouched suffix remains queued');
    expect(commands.isEmpty, isFalse);

    expect(commands.flush, returnsNormally);
    expect(first.parent, same(root), reason: 'the prefix was not replayed');
    expect(after.parent, same(root));
    expect(commands.isEmpty, isTrue);
  });
}
