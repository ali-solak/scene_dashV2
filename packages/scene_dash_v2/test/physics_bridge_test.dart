import 'dart:async';

import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scene_dash_v2_core/advanced.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';

/// Minimal fake world: only the collision stream and lifecycle hooks are real;
/// query methods are unused and forwarded to [noSuchMethod].
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

CollisionBegan _collision() => CollisionBegan(
      nodeA: Node(),
      nodeB: Node(),
      colliderA: _Collider(),
      colliderB: _Collider(),
      contacts: const [],
    );

void main() {
  test('PhysicsEventBridge subscribes on start and disposes idempotently',
      () async {
    final world = _FakeWorld();
    final bridge = PhysicsEventBridge(world);
    expect(world.controller.hasListener, isFalse);

    bridge
      ..start()
      ..start();
    expect(world.controller.hasListener, isTrue);

    world.controller.add(_collision());
    await Future<void>.delayed(Duration.zero);
    expect(bridge.pending, 1);

    await bridge.dispose();
    await bridge.dispose();
    expect(bridge.pending, 0);
    expect(world.controller.hasListener, isFalse);

    await world.controller.close();
  });

  test('PhysicsPlugin exposes the world as an injectable resource', () {
    final world = _FakeWorld();
    final app = App()..addPlugin(PhysicsPlugin(world));
    app.start();
    expect(identical(app.world.resources.get<PhysicsWorld>(), world), isTrue);
    addTearDown(() async {
      await app.shutdown();
      await world.controller.close();
    });
  });

  test('buffers collisions and drains them into ECS events on frameStart',
      () async {
    final world = _FakeWorld();
    final app = App()..addPlugin(PhysicsPlugin(world));
    app.start();
    final reader = app.world.eventChannel<CollisionEvent>().reader();

    world.controller
      ..add(_collision())
      ..add(_collision());
    await Future<void>.delayed(Duration.zero); // let the stream deliver

    final bridge = app.world.resources.get<PhysicsEventBridge>();
    expect(bridge.pending, 2, reason: 'buffered, not yet published');

    app.runSchedule(Schedules.frameStart); // drain system runs
    expect(bridge.pending, 0);

    final events = reader.drain();
    expect(events, hasLength(2));
    expect(events.first, isA<CollisionBegan>());

    await world.controller.close();
  });

  test(
      'a collision fired during frame N physics surfaces in frame N+1 '
      '(async stream latency)', () async {
    // Documents the platform constraint (see PhysicsPlugin): flutter_scene's
    // collision controllers are async broadcast StreamControllers (verified in
    // 0.18.1 BasicPhysicsWorld and flutter_scene_rapier 0.2.1), so an event
    // added during the frame's synchronous physics window reaches the bridge
    // in a microtask *after* the frame's synchronous work — gameplay reads it
    // one frame later. If this test starts failing with the event visible in
    // frame N, upstream switched to a sync controller: move the drain and
    // resolver registrations to Schedules.postPhysics for same-frame hits.
    final world = _FakeWorld();
    final app = App()..addPlugin(PhysicsPlugin(world));
    final loop = EcsFrameLoop(app)..ensureTimeResources();
    app.start();
    final reader = app.world.eventChannel<CollisionEvent>().reader();
    final seenPerFrame = <int, int>{};
    var frame = 0;

    void runFrame(void Function() duringPhysics) {
      frame += 1;
      loop.frameStart(Duration(milliseconds: 16 * frame), 0.016);
      loop.fixedStep(1 / 60);
      duringPhysics(); // The scene's physics step window.
      loop.update(0.016);
      seenPerFrame[frame] = reader.drain().length;
    }

    // Frame 1: the physics step reports a contact.
    runFrame(() => world.controller.add(_collision()));
    // The stream delivers between frames (microtask boundary).
    await Future<void>.delayed(Duration.zero);
    // Frame 2: nothing new from physics.
    runFrame(() {});

    expect(seenPerFrame[1], 0,
        reason: 'async stream: the contact cannot be read in its own frame');
    expect(seenPerFrame[2], 1,
        reason: 'the frameStart drain of the next frame surfaces it');

    await world.controller.close();
  });

  test('shutdown cancels the physics subscription and clears pending events',
      () async {
    final world = _FakeWorld();
    final app = App()..addPlugin(PhysicsPlugin(world));
    app.start();
    expect(world.controller.hasListener, isTrue);

    final bridge = app.world.resources.get<PhysicsEventBridge>();
    world.controller.add(_collision());
    await Future<void>.delayed(Duration.zero);
    expect(bridge.pending, 1);

    await app.shutdown();
    await app.shutdown();

    expect(bridge.pending, 0);
    expect(world.controller.hasListener, isFalse);

    await world.controller.close();
  });
}
