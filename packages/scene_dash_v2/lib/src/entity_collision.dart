import 'package:flutter_scene/scene.dart' show CollisionEvent;
import 'package:scene_dash_v2_core/advanced.dart';

import 'scene_node_index.dart';

/// A collision resolved to ECS entities.
final class EntityCollision {
  /// The entity owning the source event's `nodeA`, or `null` if unmanaged.
  final Entity? a;

  /// The entity owning the source event's `nodeB`, or `null` if unmanaged.
  final Entity? b;

  /// The raw physics event this was resolved from.
  final CollisionEvent source;

  const EntityCollision(this.a, this.b, this.source);

  /// The entity paired with [entity] in this collision, or `null` when [entity]
  /// is not part of it or the other side is unmanaged. Handy when a system
  /// already holds one side (a projectile) and wants what it struck.
  Entity? other(Entity entity) {
    if (entity == a) return b;
    if (entity == b) return a;
    return null;
  }
}

/// Converts [CollisionEvent] values to [EntityCollision] values.
final class EntityCollisionPlugin extends Plugin {
  /// Label of the generated resolver system.
  final SystemLabel resolveLabel;

  /// Label of [PhysicsPlugin]'s drain system, which this runs after. Override
  /// only if the drain was registered with a non-default label.
  final SystemLabel drainLabel;

  const EntityCollisionPlugin({
    this.resolveLabel = const SystemLabel('physics.resolveCollisionEntities'),
    this.drainLabel = const SystemLabel('physics.drainEvents'),
  });

  @override
  void build(AppBuilder app) {
    app
      ..addEvent<EntityCollision>()
      ..addSystemAdapter(
        _ResolveCollisionEntitiesAdapter(),
        schedule: Schedules.frameStart,
        label: resolveLabel,
        after: [drainLabel],
      );
  }
}

/// Hand-written adapter that maps each buffered [CollisionEvent]'s nodes to
/// entities and forwards it as an [EntityCollision].
final class _ResolveCollisionEntitiesAdapter
    implements SystemAdapter, SystemAccessProvider {
  /// Reads no components.
  @override
  SystemAccess get access => SystemAccess.empty;

  late final EventReader<CollisionEvent> _reader;
  late final EventChannel<EntityCollision> _channel;
  late final EventWriter<EntityCollision> _writer;
  late final SceneNodeIndex _index;

  @override
  void initialize(World world) {
    _reader = world.eventChannel<CollisionEvent>().reader();
    _channel = world.eventChannel<EntityCollision>();
    _writer = _channel.writer();
    _index = world.resources.get<SceneNodeIndex>();
  }

  @override
  void run() {
    // Skip collision mapping when nothing reads it.
    if (!_channel.hasReaders) {
      _reader.consume();
      return;
    }
    _reader.forEach((event) {
      final a = _index.entityOf(event.nodeA);
      final b = _index.entityOf(event.nodeB);
      if (a == null && b == null) return; // neither side is ECS-managed
      _writer.send(EntityCollision(a, b, event));
    });
  }
}
