import 'dart:async';

import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scene_dash_v2_core/advanced.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';

/// Minimal fake world: only the collision stream and lifecycle hooks are real.
final class _FakeWorld extends PhysicsWorld {
  final controller = StreamController<CollisionEvent>.broadcast();

  @override
  String get backendName => 'fake';

  @override
  Stream<CollisionEvent> get collisions => controller.stream;

  @override
  void step(double fixedDt) {}

  @override
  void interpolateTransforms(double alpha) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Collider extends Component {}

CollisionBegan _began(Node a, Node b) => CollisionBegan(
      nodeA: a,
      nodeB: b,
      colliderA: _Collider(),
      colliderB: _Collider(),
      contacts: const [],
    );

/// Starts an app with the physics bridge and the entity-collision layer, seeded
/// with a [SceneNodeIndex] over [bindings] (a `Game` normally maintains it).
({App app, _FakeWorld physics, EventReader<EntityCollision> reader}) _start(
  Map<Node, Entity> Function(World world) bindings,
) {
  final physics = _FakeWorld();
  final app = App()
    ..addPlugin(PhysicsPlugin(physics))
    ..addPlugin(const EntityCollisionPlugin());
  app.world.resources.insert<SceneNodeIndex>(SceneNodeIndex(bindings(app.world)));
  app.start();
  return (
    app: app,
    physics: physics,
    reader: app.world.eventChannel<EntityCollision>().reader(),
  );
}

void main() {
  test('republishes a collision with both nodes resolved to entities', () async {
    final nodeA = Node();
    final nodeB = Node();
    late Entity entityA;
    late Entity entityB;
    final started = _start((world) {
      entityA = world.entities.spawn();
      entityB = world.entities.spawn();
      return {nodeA: entityA, nodeB: entityB};
    });
    addTearDown(() async {
      await started.app.shutdown();
      await started.physics.controller.close();
    });

    started.physics.controller.add(_began(nodeA, nodeB));
    await Future<void>.delayed(Duration.zero); // let the stream deliver

    started.app.runSchedule(Schedules.frameStart); // drain, then resolve

    final events = started.reader.drain();
    expect(events, hasLength(1));
    expect(events.single.a, entityA);
    expect(events.single.b, entityB);
    expect(events.single.source, isA<CollisionBegan>());
  });

  test('resolves the bound side and leaves an unmanaged collider null',
      () async {
    final bound = Node();
    final unmanaged = Node(); // never indexed
    late Entity entity;
    final started = _start((world) {
      entity = world.entities.spawn();
      return {bound: entity};
    });
    addTearDown(() async {
      await started.app.shutdown();
      await started.physics.controller.close();
    });

    started.physics.controller.add(_began(bound, unmanaged));
    await Future<void>.delayed(Duration.zero);
    started.app.runSchedule(Schedules.frameStart);

    final event = started.reader.drain().single;
    expect(event.a, entity);
    expect(event.b, isNull);
    expect(event.other(entity), isNull); // the other side is unmanaged
  });

  test('drops a collision where neither node maps to an entity', () async {
    final started = _start((_) => const {});
    addTearDown(() async {
      await started.app.shutdown();
      await started.physics.controller.close();
    });

    started.physics.controller.add(_began(Node(), Node()));
    await Future<void>.delayed(Duration.zero);
    started.app.runSchedule(Schedules.frameStart);

    expect(started.reader.drain(), isEmpty);
  });

  test('other() returns the opposite side of the pair', () {
    final a = Entity(1, 0);
    final b = Entity(2, 0);
    final collision = EntityCollision(a, b, _began(Node(), Node()));
    expect(collision.other(a), b);
    expect(collision.other(b), a);
    expect(collision.other(Entity(9, 0)), isNull);
  });
}
