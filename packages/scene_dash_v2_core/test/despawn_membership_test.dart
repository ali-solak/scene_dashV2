import 'package:scene_dash_v2_core/advanced.dart';
import 'package:test/test.dart';

final class Slot<T> {}

void _registerNested<T>(StoreRegistry stores, int depth) {
  stores.ensureTag<T>();
  if (depth > 1) _registerNested<Slot<T>>(stores, depth - 1);
}

void main() {
  test('despawn strips stores across membership words, sparing others', () {
    final world = World();
    _registerNested<Slot<void>>(world.stores, 70);
    final doomed = world.entities.spawn();
    final kept = world.entities.spawn();
    const doomedIn = [0, 31, 32, 33, 64, 69];
    const keptIn = [0, 32, 69, 5];
    for (final id in doomedIn) {
      (world.stores.storeAt(id) as TagStore).add(doomed.index);
    }
    for (final id in keptIn) {
      (world.stores.storeAt(id) as TagStore).add(kept.index);
    }

    world.despawnNow(doomed);

    for (var id = 0; id < 70; id++) {
      final store = world.stores.storeAt(id);
      expect(store.containsIndex(doomed.index), isFalse, reason: 'store $id');
      expect(store.containsIndex(kept.index), keptIn.contains(id));
    }
  });

  test('a store registered with rows keeps them despawnable', () {
    final world = World();
    final store = ObjectComponentStore<int>()..insert(3, 7);
    while (world.entities.slotCount < 4) {
      world.entities.spawn();
    }
    world.stores.register<int>(store);
    world.despawnNow(world.entities.resolve(3));
    expect(store.length, 0);
  });

  test('clear forgets membership so a reused index starts clean', () {
    final world = World();
    final health = world.ensureObjectStore<int>();
    final tags = world.ensureTagStore<Slot<int>>();
    final entity = world.entities.spawn();
    health.insert(entity.index, 1);
    tags.add(entity.index);
    world.reset();
    final reused = world.entities.spawn();
    health.insert(reused.index, 2);
    world.despawnNow(reused);
    expect(health.length, 0);
    expect(tags.length, 0);
  });
}
