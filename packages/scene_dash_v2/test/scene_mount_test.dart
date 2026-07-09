import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scene_dash_v2_core/advanced.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';

World _worldWithBinding(Node node) {
  final world = World()
    ..stores.register<SceneNode>(ObjectComponentStore<SceneNode>());
  final entity = world.entities.spawn();
  world.insertNow<SceneNode>(entity, SceneNode(node));
  return world;
}

void main() {
  test('mounts an unparented bound node under the root, once', () {
    final root = Node();
    final commands = SceneCommands(root);
    final node = Node();
    final world = _worldWithBinding(node);

    final adapter = SceneNodeMountAdapter(commands, <Node, Entity>{})
      ..initialize(world);

    adapter.run();
    expect(node.parent, isNull, reason: 'queued, not yet flushed');
    commands.flush();
    expect(node.parent, same(root));

    // Already parented → nothing more is queued.
    adapter.run();
    expect(commands.isEmpty, isTrue);
  });

  test('leaves a node the game parented itself alone', () {
    final root = Node();
    final elsewhere = Node()..add(Node());
    root.add(elsewhere);
    final commands = SceneCommands(root);

    final node = Node();
    elsewhere.add(node); // custom parenting
    final world = World()
      ..stores.register<SceneNode>(ObjectComponentStore<SceneNode>());
    final entity = world.entities.spawn();
    world.insertNow<SceneNode>(entity, SceneNode(node));

    SceneNodeMountAdapter(commands, <Node, Entity>{})
      ..initialize(world)
      ..run();

    expect(commands.isEmpty, isTrue, reason: 'already parented');
    expect(node.parent, same(elsewhere));
    expect(world.has<Mounted>(entity), isTrue);
  });

  test('detaches a mounted node when its entity is despawned', () {
    final root = Node();
    final commands = SceneCommands(root);
    final node = Node();
    final world = World()
      ..stores.register<SceneNode>(ObjectComponentStore<SceneNode>());
    final entity = world.entities.spawn();
    world.insertNow<SceneNode>(entity, SceneNode(node));

    final adapter = SceneNodeMountAdapter(commands, <Node, Entity>{})
      ..initialize(world);
    adapter.run();
    commands.flush();
    expect(node.parent, same(root), reason: 'mounted on spawn');

    world.despawnNow(entity);
    adapter.run();
    expect(commands.isEmpty, isFalse, reason: 'detach queued');
    commands.flush();
    expect(node.parent, isNull, reason: 'detached on despawn');
  });

  test('detaches when the SceneNode component is removed', () {
    final root = Node();
    final commands = SceneCommands(root);
    final node = Node();
    final world = World()
      ..stores.register<SceneNode>(ObjectComponentStore<SceneNode>());
    final entity = world.entities.spawn();
    world.insertNow<SceneNode>(entity, SceneNode(node));

    final adapter = SceneNodeMountAdapter(commands, <Node, Entity>{})
      ..initialize(world);
    adapter.run();
    commands.flush();
    expect(node.parent, same(root));

    // Remove just the component (entity stays alive).
    world.removeNow<SceneNode>(entity);
    adapter.run();
    commands.flush();
    expect(node.parent, isNull, reason: 'detached on component removal');
  });

  test('detaches the old node and mounts the new one on replacement', () {
    final root = Node();
    final commands = SceneCommands(root);
    final oldNode = Node();
    final world = World()
      ..stores.register<SceneNode>(ObjectComponentStore<SceneNode>());
    final entity = world.entities.spawn();
    world.insertNow<SceneNode>(entity, SceneNode(oldNode));

    final adapter = SceneNodeMountAdapter(commands, <Node, Entity>{})
      ..initialize(world);
    adapter.run();
    commands.flush();
    expect(oldNode.parent, same(root));

    final newNode = Node();
    world.insertNow<SceneNode>(entity, SceneNode(newNode)); // replace
    adapter.run();
    commands.flush();
    expect(oldNode.parent, isNull, reason: 'old node detached');
    expect(newNode.parent, same(root), reason: 'new node mounted');
  });

  test('tags the entity Mounted on mount and clears it on despawn', () {
    final root = Node();
    final commands = SceneCommands(root);
    final node = Node();
    final world = World()
      ..stores.register<SceneNode>(ObjectComponentStore<SceneNode>());
    final entity = world.entities.spawn();
    world.insertNow<SceneNode>(entity, SceneNode(node));

    final adapter = SceneNodeMountAdapter(commands, <Node, Entity>{})
      ..initialize(world);
    expect(world.has<Mounted>(entity), isFalse);

    adapter.run();
    expect(world.has<Mounted>(entity), isTrue, reason: 'tagged on mount');

    world.despawnNow(entity); // strips Mounted with every other store
    adapter.run();
    expect(world.isAlive(entity), isFalse);
  });

  test('clears Mounted when only the SceneNode component is removed', () {
    final root = Node();
    final commands = SceneCommands(root);
    final node = Node();
    final world = World()
      ..stores.register<SceneNode>(ObjectComponentStore<SceneNode>());
    final entity = world.entities.spawn();
    world.insertNow<SceneNode>(entity, SceneNode(node));

    final adapter = SceneNodeMountAdapter(commands, <Node, Entity>{})
      ..initialize(world);
    adapter.run();
    expect(world.has<Mounted>(entity), isTrue);

    world.removeNow<SceneNode>(entity); // entity stays alive
    adapter.run();
    expect(world.has<Mounted>(entity), isFalse, reason: 'untagged on unmount');
  });

  test('keeps the entity Mounted across a node replacement', () {
    final root = Node();
    final commands = SceneCommands(root);
    final world = World()
      ..stores.register<SceneNode>(ObjectComponentStore<SceneNode>());
    final entity = world.entities.spawn();
    world.insertNow<SceneNode>(entity, SceneNode(Node()));

    final adapter = SceneNodeMountAdapter(commands, <Node, Entity>{})
      ..initialize(world);
    adapter.run();
    commands.flush();
    expect(world.has<Mounted>(entity), isTrue);

    world.insertNow<SceneNode>(entity, SceneNode(Node())); // replace node
    adapter.run();
    expect(world.has<Mounted>(entity), isTrue, reason: 'still mounted');
  });

  test('maintains a node -> entity index, resolving nested child meshes', () {
    final root = Node();
    final commands = SceneCommands(root);
    final child = Node();
    final node = Node()..add(child); // child mesh under the bound node
    final world = World()
      ..stores.register<SceneNode>(ObjectComponentStore<SceneNode>());
    final entity = world.entities.spawn();
    world.insertNow<SceneNode>(entity, SceneNode(node));

    final map = <Node, Entity>{};
    final index = SceneNodeIndex(map);
    SceneNodeMountAdapter(commands, map)
      ..initialize(world)
      ..run();

    expect(index.entityOf(node), entity, reason: 'direct bound node');
    expect(index.entityOf(child), entity, reason: 'walks up to the bound node');
    expect(index.length, 1);
  });

  test('drops index entries when their entity is despawned', () {
    final root = Node();
    final commands = SceneCommands(root);
    final node = Node();
    final world = World()
      ..stores.register<SceneNode>(ObjectComponentStore<SceneNode>());
    final entity = world.entities.spawn();
    world.insertNow<SceneNode>(entity, SceneNode(node));

    final map = <Node, Entity>{};
    final index = SceneNodeIndex(map);
    final adapter = SceneNodeMountAdapter(commands, map)..initialize(world);
    adapter.run();
    expect(index.entityOf(node), entity);

    world.despawnNow(entity);
    adapter.run();
    expect(index.entityOf(node), isNull, reason: 'pruned after despawn');
    expect(index.length, 0);
  });

  test('World.reset detaches auto-mounted nodes on the next run', () {
    final root = Node();
    final commands = SceneCommands(root);
    final node = Node();
    final world = _worldWithBinding(node);

    final adapter = SceneNodeMountAdapter(commands, <Node, Entity>{})
      ..initialize(world);
    adapter.run();
    commands.flush();
    expect(node.parent, same(root), reason: 'mounted before the reset');

    world.reset();
    // The reset bumped the SceneNode store's revision, so the adapter's
    // next (revision-gated) run reconciles and queues the detach — no manual
    // scene cleanup.
    adapter.run();
    commands.flush();

    expect(node.parent, isNull, reason: 'detached after reset');
    expect(world.ensureTagStore<Mounted>().length, 0);
  });

  test('does not auto-detach a game-parented node when despawned', () {
    final root = Node();
    final elsewhere = Node();
    root.add(elsewhere);
    final commands = SceneCommands(root);

    final node = Node();
    elsewhere.add(node); // custom parenting → never adopted
    final world = World()
      ..stores.register<SceneNode>(ObjectComponentStore<SceneNode>());
    final entity = world.entities.spawn();
    world.insertNow<SceneNode>(entity, SceneNode(node));

    final adapter = SceneNodeMountAdapter(commands, <Node, Entity>{})
      ..initialize(world);
    adapter.run();
    world.despawnNow(entity);
    adapter.run();
    commands.flush();

    expect(node.parent, same(elsewhere), reason: 'game owns this node');
  });
}
