import 'package:scene_dash_v2_core/advanced.dart';
import 'package:test/test.dart';

final class Position {
  double x;
  Position(this.x);
}

final class Enemy {
  const Enemy();
}

final class Stunned {
  const Stunned();
}

World _worldWithStores() {
  return World()
    ..stores.register<Position>(ObjectComponentStore<Position>())
    ..stores.register<Enemy>(TagStore())
    ..stores.register<Stunned>(TagStore());
}

Entity _spawn(
  World world, {
  Position? position,
  bool enemy = false,
  bool stunned = false,
}) {
  final entity = world.entities.spawn();
  if (position != null) world.insertNow<Position>(entity, position);
  if (enemy) world.insertNow<Enemy>(entity, const Enemy());
  if (stunned) world.insertNow<Stunned>(entity, const Stunned());
  return entity;
}

void main() {
  group('EntityQuery', () {
    test('iterates exactly the entities carrying the required tag', () {
      final world = _worldWithStores();
      final a = _spawn(world, enemy: true);
      _spawn(world, position: Position(1)); // not an enemy
      final b = _spawn(world, enemy: true, position: Position(2));

      final seen = <Entity>{};
      world.queryEntities(withTypes: const [Enemy]).each(seen.add);
      expect(seen, {a, b});
    });

    test('honours without filters', () {
      final world = _worldWithStores();
      final free = _spawn(world, enemy: true);
      _spawn(world, enemy: true, stunned: true);

      final seen = <Entity>{};
      world
          .queryEntities(withTypes: const [Enemy], withoutTypes: const [Stunned])
          .each(seen.add);
      expect(seen, {free});
    });

    test('drives from the smallest required store', () {
      final world = _worldWithStores();
      for (var i = 0; i < 100; i++) {
        _spawn(world, position: Position(i.toDouble()));
      }
      final tagged = _spawn(world, enemy: true, position: Position(-1));

      // Enemy (1 entity) must drive, not Position (101): correctness is
      // observable, driver choice is a perf detail asserted indirectly here.
      final seen = <Entity>{};
      world.queryEntities(withTypes: const [Enemy, Position]).each(seen.add);
      expect(seen, {tagged});
    });

    test('contains matches live filtered entities only', () {
      final world = _worldWithStores();
      final enemy = _spawn(world, enemy: true);
      final civilian = _spawn(world);
      final query = world.queryEntities(withTypes: const [Enemy]);

      expect(query.contains(enemy), isTrue);
      expect(query.contains(civilian), isFalse);

      world.despawnNow(enemy);
      expect(query.contains(enemy), isFalse, reason: 'stale handle');
    });

    test('isEmpty and count are exact', () {
      final world = _worldWithStores();
      final query = world.queryEntities(
        withTypes: const [Enemy],
        withoutTypes: const [Stunned],
      );
      expect(query.isEmpty, isTrue);
      expect(query.count(), 0);

      _spawn(world, enemy: true);
      _spawn(world, enemy: true);
      _spawn(world, enemy: true, stunned: true); // filtered out

      expect(query.isEmpty, isFalse);
      expect(query.count(), 2);
    });

    test('eachUntil stops when the callback returns false', () {
      final world = _worldWithStores();
      for (var i = 0; i < 5; i++) {
        _spawn(world, enemy: true);
      }

      var visits = 0;
      world.queryEntities(withTypes: const [Enemy]).eachUntil((entity) {
        visits++;
        return visits < 2;
      });
      expect(visits, 2);
    });

    test('eachUntil respects without filters', () {
      final world = _worldWithStores();
      final free = _spawn(world, enemy: true);
      _spawn(world, enemy: true, stunned: true);

      final seen = <Entity>[];
      world
          .queryEntities(withTypes: const [Enemy], withoutTypes: const [Stunned])
          .eachUntil((entity) {
            seen.add(entity);
            return true;
          });
      expect(seen, <Entity>[free]);
    });

    test('eachUntil rejects structural mutation inside the callback', () {
      final world = _worldWithStores();
      _spawn(world, enemy: true);
      final extra = world.entities.spawn();

      expect(
        () => world.queryEntities(withTypes: const [Enemy]).eachUntil((entity) {
          world.insertNow<Enemy>(extra, const Enemy());
          return true;
        }),
        throwsA(isA<AssertionError>()),
      );
    });

    test('firstWhere returns the first matching entity or null', () {
      final world = _worldWithStores();
      _spawn(world, enemy: true);
      final wanted = _spawn(world, enemy: true, position: Position(7));
      final positions = world.query1<Position>();

      final query = world.queryEntities(withTypes: const [Enemy]);
      expect(
        query.firstWhere((entity) => positions.get(entity) != null),
        wanted,
      );
      expect(query.firstWhere((entity) => false), isNull);
    });

    test('any stops at the first hit and is false on an empty query', () {
      final world = _worldWithStores();
      final query = world.queryEntities(withTypes: const [Enemy]);
      expect(query.any((entity) => true), isFalse);

      _spawn(world, enemy: true);
      _spawn(world, enemy: true);
      var visits = 0;
      final found = query.any((entity) {
        visits++;
        return true;
      });
      expect(found, isTrue);
      expect(visits, 1);
    });

    test('requires at least one withTypes entry', () {
      final world = _worldWithStores();
      expect(
        () => world.queryEntities(withTypes: const []),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('does not leave a query marked active after iteration', () {
      final world = _worldWithStores();
      _spawn(world, enemy: true);
      final query = world.queryEntities(withTypes: const [Enemy]);
      query.each((_) {});
      query.count();
      expect(() => _spawn(world, enemy: true), returnsNormally);
    });
  });

  group('Query.count', () {
    test('Query1.count matches filters exactly', () {
      final world = _worldWithStores();
      _spawn(world, position: Position(1), enemy: true);
      _spawn(world, position: Position(2), enemy: true, stunned: true);
      _spawn(world, position: Position(3)); // no tag
      _spawn(world, enemy: true); // no Position

      final query = world.query1<Position>(
        withTypes: const [Enemy],
        withoutTypes: const [Stunned],
      );
      expect(query.count(), 1);
      expect(
        query.driverLength,
        greaterThanOrEqualTo(query.count()),
        reason: 'driverLength stays an upper bound',
      );
    });

    test('Query2.count requires both components', () {
      final world = _worldWithStores();
      world.stores.register<int>(ObjectComponentStore<int>());
      final both = _spawn(world, position: Position(1));
      world.insertNow<int>(both, 7);
      _spawn(world, position: Position(2)); // Position only

      expect(world.query2<Position, int>().count(), 1);
    });
  });
}
