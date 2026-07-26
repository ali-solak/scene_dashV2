import '../schedule/system_label.dart';
import '../storage/object_store.dart';
import '../system/system_access.dart';
import '../system/system_adapter.dart';
import '../time/frame_time.dart';
import '../world/world.dart';

/// Despawns an entity after [remaining] seconds.
final class DespawnAfter {
  /// Seconds of game time left before the entity is despawned. Mutable:
  /// systems may extend or shorten an in-flight lifetime.
  double remaining;

  DespawnAfter(this.remaining);
}

/// Advances all [DespawnAfter] timers.
final class DespawnAfterSystem implements SystemAdapter, SystemAccessProvider {
  /// The registration label, so games can order systems `before`/`after` the
  /// built-in tick.
  static const SystemLabel label = SystemLabel('scene_dash.despawnAfter');

  @override
  SystemAccess get access => const SystemAccess(writes: <Type>{DespawnAfter});

  late World _world;
  late ObjectComponentStore<DespawnAfter> _store;

  @override
  void initialize(World world) {
    _world = world;
    _store = world.ensureObjectStore<DespawnAfter>();
  }

  @override
  void run() {
    if (_store.length == 0) return;
    final delta = _world.resource<FrameTime>().delta;
    for (var dense = 0; dense < _store.length; dense++) {
      final lifetime = _store.valueAt(dense);
      lifetime.remaining -= delta;
      if (lifetime.remaining <= 0) {
        _world.commands.despawn(
          _world.entities.resolve(_store.entityIndexAt(dense)),
        );
      }
    }
  }
}
