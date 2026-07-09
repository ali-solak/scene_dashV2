import '../schedule/system_label.dart';
import '../storage/object_store.dart';
import '../system/system_access.dart';
import '../system/system_adapter.dart';
import '../time/frame_time.dart';
import '../world/world.dart';

/// Gives an entity a lifetime: after [remaining] seconds of game time it is
/// despawned automatically — the timed sibling of [DespawnOnExit]'s
/// state-scoped teardown.
///
/// The staple for muzzle flashes, pickups, corpses, projectiles with a max
/// range — anything spawned in volume that must go away on its own without a
/// bespoke countdown system:
///
/// ```dart
/// commands.spawn(ExplosionVfxBundle(at: hit.point))
///   ..insert(DespawnAfter(0.4));
/// ```
///
/// A built-in system (registered by `App` in `Schedules.update`) ticks
/// [remaining] down by `FrameTime.delta` and queues a *deferred* despawn when
/// it reaches zero, so the entity is fully alive for the frame it expires on
/// and vanishes at the schedule's command flush. Because game time drives it,
/// pause/hitstop/slow motion extend the lifetime with everything else.
/// Removing the component before it expires cancels the despawn.
///
/// The countdown is frame-time by design; for fixed-step determinism, tick a
/// game-defined copy in a fixed schedule instead.
final class DespawnAfter {
  /// Seconds of game time left before the entity is despawned. Mutable:
  /// systems may extend or shorten an in-flight lifetime.
  double remaining;

  DespawnAfter(this.remaining);
}

/// The built-in ticker behind [DespawnAfter]. `App` registers one in
/// `Schedules.update` under [label]; game code never constructs it.
///
/// Iterates the [DespawnAfter] store directly (allocation-free, like the
/// state-scoped despawn walk) and defers every despawn through `Commands` —
/// never a mid-iteration structural change. Requires a [FrameTime] resource
/// once any entity carries [DespawnAfter]: the standard driver inserts one,
/// headless apps insert their own; it throws rather than silently freezing
/// lifetimes.
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
