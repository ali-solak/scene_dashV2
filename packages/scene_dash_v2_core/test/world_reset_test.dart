import 'package:scene_dash_v2_core/advanced.dart';
import 'package:test/test.dart';

final class Position {
  double x;
  Position(this.x);
}

final class Enemy implements Tag {
  const Enemy();
}

final class Score {
  int value = 0;
}

World _worldWithStores() {
  return World()
    ..stores.register<Position>(ObjectComponentStore<Position>())
    ..stores.register<Enemy>(TagStore());
}

void main() {
  group('World.reset', () {
    test('stale handles reject after reset', () {
      final world = _worldWithStores();
      final e = world.entities.spawn();
      world.insertNow<Position>(e, Position(1));

      world.reset();

      expect(world.isAlive(e), isFalse);
      expect(world.tryGet<Position>(e), isNull);
      expect(world.query1<Position>().get(e), isNull);
    });

    test('stores are emptied but stay registered, with a revision bump', () {
      final world = _worldWithStores();
      final e = world.entities.spawn();
      world.insertNow<Position>(e, Position(1));
      world.insertNow<Enemy>(e, const Enemy());
      final store = world.stores.object<Position>();
      final revisionBefore = store.revision;

      world.reset();

      expect(store.length, 0);
      expect(world.stores.isRegistered(Position), isTrue);
      expect(world.stores.isRegistered(Enemy), isTrue);
      expect(
        store.revision,
        greaterThan(revisionBefore),
        reason: 'revision bump is what integration caches key off',
      );
      expect(world.query1<Position>().isEmpty, isTrue);
      expect(world.queryEntities(withTypes: const [Enemy]).isEmpty, isTrue);
    });

    test('an already-empty store keeps its revision across reset', () {
      final world = _worldWithStores();
      final store = world.stores.object<Position>();
      final revisionBefore = store.revision;
      world.reset();
      expect(store.revision, revisionBefore);
    });

    test('spawns after reset reuse slots with bumped generations', () {
      final world = _worldWithStores();
      final before = <Entity>[
        for (var i = 0; i < 3; i++) world.entities.spawn(),
      ];

      world.reset();
      expect(world.entities.aliveCount, 0);

      final after = <Entity>[
        for (var i = 0; i < 3; i++) world.entities.spawn(),
      ];
      // Slots are reused rather than growing the registry...
      expect(
        after.map((e) => e.index).toSet(),
        before.map((e) => e.index).toSet(),
      );
      // ...at a new generation, so the old handles stay rejected.
      for (final old in before) {
        expect(world.isAlive(old), isFalse);
      }
      for (final fresh in after) {
        expect(world.isAlive(fresh), isTrue);
      }
    });

    test('event readers created before reset read nothing after', () {
      final world = _worldWithStores()..registerEvent<String>();
      final channel = world.eventChannel<String>();
      final reader = channel.reader();
      channel.send('before');

      world.reset();

      expect(reader.hasUnread, isFalse);
      expect(reader.drain(), isEmpty);

      // The reader stays registered: new events flow normally.
      channel.send('after');
      expect(reader.drain(), <String>['after']);
    });

    test('keepResources: true (default) preserves resources', () {
      final world = _worldWithStores();
      final score = Score()..value = 7;
      world.resources.insert<Score>(score);

      world.reset();

      expect(world.resource<Score>(), same(score));
      expect(world.resource<Score>().value, 7);
    });

    test('keepResources: false drops every resource', () {
      final world = _worldWithStores();
      world.resources.insert<Score>(Score());

      world.reset(keepResources: false);

      expect(world.hasResource<Score>(), isFalse);
    });

    test('asserts when deferred commands are pending', () {
      final world = _worldWithStores();
      final e = world.entities.spawn();
      world.commands.insert<Position>(e, Position(1));

      expect(() => world.reset(), throwsA(isA<AssertionError>()));

      // After flushing, reset proceeds.
      world.commands.apply();
      expect(() => world.reset(), returnsNormally);
    });
  });

  group('World.despawnAll', () {
    test('fires removal observers and preserves events and resources', () {
      final world = _worldWithStores()..registerEvent<String>();
      final score = Score()..value = 7;
      world.resources.insert<Score>(score);
      final removedPositions = <int>[];
      final removedEnemies = <int>[];
      ObserverRegistry.of(world)
        ..observe<Position>(
          onRemove: (w, entity, position) => removedPositions.add(entity.index),
        )
        ..observe<Enemy>(
          onRemove: (w, entity, enemy) => removedEnemies.add(entity.index),
        );
      final first = world.entities.spawn();
      final second = world.entities.spawn();
      world
        ..insertNow<Position>(first, Position(1))
        ..insertNow<Enemy>(first, const Enemy())
        ..insertNow<Position>(second, Position(2));
      final reader = world.eventChannel<String>().reader();
      world.sendEvent('kept');

      world.despawnAll();

      expect(world.entities.aliveCount, 0);
      expect(world.isAlive(first), isFalse);
      expect(world.isAlive(second), isFalse);
      expect(removedPositions, [first.index, second.index]);
      expect(removedEnemies, [first.index]);
      expect(world.resource<Score>(), same(score));
      expect(reader.drain(), ['kept']);
    });

    test('skips a snapshot entity already despawned by an observer', () {
      final world = _worldWithStores();
      final first = world.entities.spawn();
      final sibling = world.entities.spawn();
      final removals = <int>[];
      ObserverRegistry.of(world).observe<Position>(
        onRemove: (w, entity, position) {
          removals.add(entity.index);
          if (entity == first && w.isAlive(sibling)) {
            w.despawnNow(sibling);
          }
        },
      );
      world
        ..insertNow<Position>(first, Position(1))
        ..insertNow<Position>(sibling, Position(2));

      expect(world.despawnAll, returnsNormally);

      expect(world.entities.aliveCount, 0);
      expect(removals, [first.index, sibling.index]);
    });

    test('asserts during a query or with pre-existing deferred commands', () {
      final querying = _worldWithStores();
      final queried = querying.entities.spawn();
      querying.insertNow<Position>(queried, Position(1));
      expect(
        () => querying.query1<Position>().each((entity, position) {
          querying.despawnAll();
        }),
        throwsA(isA<AssertionError>()),
      );

      final pending = _worldWithStores();
      final target = pending.entities.spawn();
      pending.commands.remove<Position>(target);
      expect(pending.despawnAll, throwsA(isA<AssertionError>()));
    });
  });
}
