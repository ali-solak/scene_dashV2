import 'package:scene_dash_v2_core/scene_dash_v2_core.dart';
import 'package:test/test.dart';

final class Health {
  final int value;
  const Health(this.value);
}

final class Stunned implements Tag {
  const Stunned();
}

void main() {
  test('surface and low-level operations share enqueue order', () {
    final world = World()..ensureObjectStore<Health>();
    final entity = world.spawn([const Health(1)]);
    world.commands.insert(entity, const Health(2));
    world.add(entity, const Health(3));
    world.commands.apply();
    expect(world.get<Health>(entity).value, 3);

    world.add(entity, const Health(4));
    world.remove<Health>(entity);
    SpawnQueue.of(world).flush();
    expect(world.has<Health>(entity), isFalse);

    world.remove<Health>(entity);
    world.add(entity, const Health(5));
    SpawnQueue.of(world).flush();
    expect(world.get<Health>(entity).value, 5);
  });

  test('add then remove also cancels an unclaimed part', () {
    final world = World();
    final entity = world.spawn([const Health(1)]);
    world.remove<Health>(entity);
    SpawnQueue.of(world).flush();
    expect(world.query<Health>().count(), 0);
  });

  test('a replacement after removing an unclaimed part is retained', () {
    final world = World();
    final entity = world.spawn([const Health(1)]);
    world.remove<Health>(entity);
    world.add(entity, const Health(2));
    SpawnQueue.of(world).flush();
    expect(world.query<Health>().single.$2.value, 2);
  });

  test('tag observers see add then remove in order', () {
    final world = World();
    final seen = <String>[];
    world.observers.observe<Stunned>(
      onAdd: (_, _, _) => seen.add('add'),
      onRemove: (_, _, _) => seen.add('remove'),
    );
    final entity = world.spawn([const Stunned()]);
    world.remove<Stunned>(entity);
    SpawnQueue.of(world).flush();
    expect(seen, ['add', 'remove']);
    expect(world.has<Stunned>(entity), isFalse);
  });

  test('queue reset cancels old additions but accepts new ones', () {
    final world = World()..ensureObjectStore<Health>();
    final queue = SpawnQueue.of(world);
    final entity = world.spawn([const Health(1)]);
    queue.reset();
    world.add(entity, const Health(2));
    queue.flush();
    expect(world.get<Health>(entity).value, 2);
  });

  test('a failed part is discarded without replaying its prefix', () {
    final world = World()..ensureObjectStore<Health>();
    var adds = 0;
    world.observers.observe<Health>(onAdd: (_, _, _) => adds++);
    world.spawn([const Health(1)]);
    world.spawn([const Stunned()]); // unregistered tag
    final tail = world.spawn([const Health(2)]);
    expect(SpawnQueue.of(world).flush, throwsStateError);
    SpawnQueue.of(world).flush();
    expect(adds, 2);
    expect(world.get<Health>(tail).value, 2);
    expect(world.commands.isEmpty, isTrue);
  });
}
