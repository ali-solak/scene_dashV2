import 'package:flutter_scene/physics.dart' show CollisionEvent, PhysicsWorld;
import 'package:scene_dash_v2_core/advanced.dart';

import 'physics_event_bridge.dart';

/// Sends physics collisions into ECS events.
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
  /// Reads no components.
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
