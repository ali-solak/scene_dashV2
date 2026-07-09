import 'dart:async';

import 'package:flutter_scene/scene.dart' show CollisionEvent, PhysicsWorld;
import 'package:scene_dash_v2_core/advanced.dart';

/// Buffers a [PhysicsWorld]'s collision stream so it can be republished as ECS
/// events on the schedule clock.
///
/// `flutter_scene` delivers collisions through an async [Stream]; ECS systems
/// read synchronously via `EventReader`. This bridge subscribes once and
/// accumulates events, and [drainTo] moves them into an ECS event channel when
/// a system runs. The initial implementation does **not** promise same-substep
/// delivery — events surface on the next drain.
final class PhysicsEventBridge {
  /// The physics world whose collisions are bridged.
  final PhysicsWorld world;

  List<CollisionEvent> _incoming = <CollisionEvent>[];
  List<CollisionEvent> _draining = <CollisionEvent>[];
  StreamSubscription<CollisionEvent>? _subscription;

  PhysicsEventBridge(this.world);

  /// Number of events currently buffered.
  int get pending => _incoming.length;

  /// Starts listening to the physics world's collision stream.
  void start() {
    if (_subscription != null) return;
    _subscription = world.collisions.listen(_incoming.add);
  }

  /// Sends all buffered events to [writer] and clears the buffer.
  void drainTo(EventWriter<CollisionEvent> writer) {
    if (_incoming.isEmpty) return;
    final oldDraining = _draining;
    _draining = _incoming;
    _incoming = oldDraining;
    for (var i = 0; i < _draining.length; i++) {
      writer.send(_draining[i]);
    }
    _draining.clear();
  }

  /// Cancels the collision-stream subscription.
  Future<void> dispose() async {
    final subscription = _subscription;
    _subscription = null;
    _incoming.clear();
    _draining.clear();
    await subscription?.cancel();
  }
}
