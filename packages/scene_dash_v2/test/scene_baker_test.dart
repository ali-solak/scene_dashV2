// Scene-authored components crossing into the ECS: the read-side walk and
// the baker that spawns an entity per authored node.
import 'package:flutter/foundation.dart' show debugPrint, debugPrintThrottled;
import 'package:flutter_scene/scene.dart' show Component, Node;
import 'package:flutter_test/flutter_test.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';

/// Stands in for a codegen'd `@SceneComponent`.
final class _Torch extends Component {
  _Torch({this.group = 'default'});
  final String group;
}

final class _Unrelated extends Component {}

/// Runtime state the authored component should not own.
final class _Flicker {
  double phase = 0;
}

/// root -> a(_Torch) -> b(_Torch, _Unrelated), plus c(nothing).
({Node root, Node a, Node b, Node c}) _tree() {
  final a = Node(name: 'a')..addComponent(_Torch(group: 'hall'));
  final b = Node(name: 'b')
    ..addComponent(_Torch(group: 'crypt'))
    ..addComponent(_Unrelated());
  final c = Node(name: 'c');
  final root = Node(name: 'root')
    ..add(a..add(b))
    ..add(c);
  return (root: root, a: a, b: b, c: c);
}

void main() {
  group('sceneComponents', () {
    test('walks the whole subtree and pairs each component with its node', () {
      final t = _tree();
      final world = World();

      final found = world.sceneComponents<_Torch>(root: t.root).toList();

      expect(found.length, 2);
      expect(found.map((e) => e.$1), containsAll(<Node>[t.a, t.b]));
      expect(
        found.map((e) => e.$2.group),
        containsAll(<String>['hall', 'crypt']),
      );
    });

    test('scopes to the given root', () {
      final t = _tree();
      final world = World();

      final found = world.sceneComponents<_Torch>(root: t.b).toList();

      expect(found.length, 1, reason: 'b is a leaf carrying one torch');
      expect(found.single.$1, same(t.b));
    });

    test('ignores nodes without the component', () {
      final t = _tree();
      final world = World();

      expect(world.sceneComponents<_Torch>(root: t.c), isEmpty);
      expect(world.sceneComponents<_Unrelated>(root: t.root).length, 1);
    });

    test('is empty with no scene and no root, so headless games are safe', () {
      expect(World().sceneComponents<_Torch>(), isEmpty);
    });

    test('is lazy: breaking out stops the walk', () {
      final t = _tree();
      var visited = 0;
      for (final _ in World().sceneComponents<_Torch>(root: t.root)) {
        visited++;
        break;
      }
      expect(visited, 1);
    });
  });

  group('bakeSceneComponents', () {
    test('spawns one entity per authored node, carrying node and data', () {
      final t = _tree();
      final game = TestGame.headless(
        features: [
          (game) => game
            ..registerComponent<_Torch>()
            ..registerComponent<NodeRef>(),
        ],
      )..start();

      final spawned = game.world.bakeSceneComponents<_Torch>(root: t.root);
      game.pump();

      expect(spawned, 2);
      final rows = game.world.query2<_Torch, NodeRef>().records.toList();
      expect(rows.length, 2);
      expect(
        rows.map((r) => r.$3.node),
        containsAll(<Node>[t.a, t.b]),
        reason: 'each entity points back at the node it came from',
      );
    });

    test('is idempotent, so a re-bake only picks up new nodes', () {
      final t = _tree();
      final game = TestGame.headless(
        features: [
          (game) => game
            ..registerComponent<_Torch>()
            ..registerComponent<NodeRef>(),
        ],
      )..start();

      expect(game.world.bakeSceneComponents<_Torch>(root: t.root), 2);
      expect(
        game.world.bakeSceneComponents<_Torch>(root: t.root),
        0,
        reason: 'already-baked nodes are skipped',
      );

      t.c.addComponent(_Torch(group: 'late'));
      expect(
        game.world.bakeSceneComponents<_Torch>(root: t.root),
        1,
        reason: 'a node mounted later still bakes',
      );
    });

    test('a custom bundle keeps runtime state off the authored component', () {
      final t = _tree();
      final game = TestGame.headless(
        features: [
          (game) => game
            ..registerComponent<_Torch>()
            ..registerComponent<_Flicker>()
            ..registerComponent<NodeRef>(),
        ],
      )..start();

      game.world.bakeSceneComponents<_Torch>(
        root: t.root,
        bundle: (node, torch) => [torch, NodeRef(node), _Flicker()],
      );
      game.pump();

      final rows = game.world.query2<_Torch, _Flicker>().records.toList();
      expect(rows.length, 2);
      expect(
        rows.map((r) => r.$3),
        everyElement(isA<_Flicker>()),
        reason: 'each entity gets its own runtime state object',
      );
    });

    test('forgetting a type lets its nodes bake again', () {
      final t = _tree();
      final game = TestGame.headless(
        features: [
          (game) => game
            ..registerComponent<_Torch>()
            ..registerComponent<NodeRef>(),
        ],
      )..start();

      game.world.bakeSceneComponents<_Torch>(root: t.root);
      game.world.resource<SceneBakeLog>().forget(_Torch);

      expect(game.world.bakeSceneComponents<_Torch>(root: t.root), 2);
    });
  });

  group('installSceneBaker', () {
    test('warns when the startup pass finds nothing', () {
      final logged = <String>[];
      debugPrint = (message, {wrapWidth}) => logged.add(message ?? '');
      addTearDown(() => debugPrint = debugPrintThrottled);

      // An explicit root runs the pass without a Scene; this one has no
      // torches under it.
      TestGame.headless(
        features: [installSceneBaker<_Torch>(root: Node(name: 'empty'))],
      ).start();

      expect(
        logged.where((m) => m.contains('sceneBaker<_Torch>')),
        isNotEmpty,
        reason: 'silence would be indistinguishable from a torchless document',
      );
      expect(logged.join(), contains('bakeSceneComponents<_Torch>()'));
    });

    test('boots clean under strictAccess', () {
      final game = TestGame.headless(
        strictAccess: true,
        features: [installSceneBaker<_Torch>()],
      )..start();

      game.pump();
      expect(
        game.world.hasResource<SceneBakeLog>(),
        isFalse,
        reason: 'headless has no Scene, so the startup pass never ran',
      );
    });
  });
}
