import 'package:flutter_scene/scene.dart' show CollisionEvent;
import 'package:scene_dash_v2_core/advanced.dart';

import 'scene_node_index.dart';

/// A physics [CollisionEvent] with its nodes already resolved back to the ECS
/// entities that own them.
///
/// The raw bridge ([PhysicsPlugin]) reports collisions as scene `Node`s, so
/// every consumer would otherwise repeat the same [SceneNodeIndex.entityOf]
/// lookup. [EntityCollisionPlugin] does it once and republishes this, so a
/// system can act on the collision — usually via `Query.get` — without touching
/// the scene graph at all.
///
/// [a] and [b] correspond to the source event's `nodeA` and `nodeB`. Either is
/// `null` when that node (or any ancestor) is not bound to an entity — a static
/// level collider, say — so a body striking unmanaged geometry still surfaces
/// the one side that resolves. [source] is the original event: pattern-match it
/// (`source is CollisionBegan`) for contacts, colliders, or to tell a solid
/// contact from a trigger or a separation.
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

/// Republishes each raw [CollisionEvent] as an [EntityCollision] with its nodes
/// resolved to entities, so systems read `EventReader<EntityCollision>` instead
/// of mapping nodes by hand.
///
/// Layer it **on top of** [PhysicsPlugin] (which owns the raw channel) and a
/// [Game] (which maintains the [SceneNodeIndex] this reads):
///
/// ```dart
/// game
///   ..addPlugin(PhysicsPlugin(physicsWorld))
///   ..addPlugin(const EntityCollisionPlugin());
/// ```
///
/// The resolver runs in [Schedules.frameStart] immediately after the raw drain.
/// Collisions drained there occurred during the previous frame's physics steps,
/// so they resolve against the node index as of that frame's final mount — the
/// entities that actually existed when the contact happened. A collider not
/// bound to an entity resolves to `null`; a collision where neither side
/// resolves is dropped rather than published.
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
  /// Reads only events and the [SceneNodeIndex] resource (updated at mount
  /// steps, not by schedule systems), so its component access is genuinely
  /// empty — declared deliberately, not left to the fallback.
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
    // Games that never read EntityCollision (immediate overlap queries
    // instead) shouldn't pay per-contact resolution: with no reader on the
    // channel the events would expire unread anyway, so just keep the raw
    // cursor advanced. Consumers register their reader at their first run,
    // one frame after boot at the latest — and physics contacts are
    // frame-late by nature, so nothing observable is missed.
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
