import 'package:flutter_scene/scene.dart' show CollisionEvent, PhysicsWorld;
import 'package:scene_dash_v2_core/advanced.dart';

import 'physics_event_bridge.dart';

/// Optional bridge from one generic `flutter_scene` [PhysicsWorld] into the ECS.
///
/// It does **not** attach the world to the scene graph — the app owns that, as
/// the `flutter_scene` examples do:
///
/// ```dart
/// final physics = BasicPhysicsWorld(); // or a backend world
/// scene.root.addComponent(physics);
/// game.addPlugin(PhysicsPlugin(physics));
/// ```
///
/// The plugin:
///
/// * inserts the [PhysicsWorld] as a resource (for raycasts / overlap queries
///   from systems via `@Resource()`);
/// * registers a raw [CollisionEvent] channel;
/// * buffers the world's collision stream and drains it into that channel each
///   frame (in [Schedules.frameStart]) so systems read collisions with
///   `EventReader<CollisionEvent>`.
///
/// **Delivery latency — a platform constraint.** The pinned `flutter_scene`
/// backends (0.18.1 `BasicPhysicsWorld`, `flutter_scene_rapier` 0.2.1) publish
/// collisions through *asynchronous* broadcast `StreamController`s: an event
/// emitted during frame N's physics steps reaches the bridge in a microtask
/// after that frame's synchronous work, so gameplay reads it in frame N+1.
/// Nothing on our side can close that gap — even a drain in
/// [Schedules.postPhysics] would run before the microtask fires. Should
/// upstream switch to sync controllers, moving the drain (and the
/// `EntityCollisionPlugin` resolver) to [Schedules.postPhysics] would deliver
/// same-frame contacts; until then registration stays at [Schedules.frameStart],
/// where the buffered events are guaranteed present. Gameplay-owned hit
/// volumes (sphere/box overlap queries on post-movement positions, as in the
/// combat slice example) are synchronous and not subject to this latency.
final class PhysicsPlugin extends Plugin {
  /// The physics world to bridge.
  final PhysicsWorld world;

  /// Label of the generated drain system.
  final SystemLabel drainLabel;

  PhysicsPlugin(
    this.world, {
    this.drainLabel = const SystemLabel('physics.drainEvents'),
  });

  @override
  void build(AppBuilder app) {
    final bridge = PhysicsEventBridge(world);
    app
      ..insertResource<PhysicsWorld>(world)
      ..insertResource<PhysicsEventBridge>(bridge)
      ..addEvent<CollisionEvent>()
      ..addSystemAdapter(
        _DrainPhysicsEventsAdapter(),
        schedule: Schedules.frameStart,
        label: drainLabel,
      )
      ..addCleanup(bridge.dispose);
  }
}

/// Hand-written adapter that flushes buffered collisions into the ECS event
/// channel each frame.
final class _DrainPhysicsEventsAdapter
    implements SystemAdapter, SystemAccessProvider {
  /// Touches only events and resources, which the access model does not
  /// cover — declared empty deliberately, not left to the fallback.
  @override
  SystemAccess get access => SystemAccess.empty;

  late final EventWriter<CollisionEvent> _writer;
  late final PhysicsEventBridge _bridge;

  @override
  void initialize(World world) {
    _writer = world.eventChannel<CollisionEvent>().writer();
    _bridge = world.resources.get<PhysicsEventBridge>()..start();
  }

  @override
  void run() => _bridge.drainTo(_writer);
}
