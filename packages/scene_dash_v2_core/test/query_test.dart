import 'package:scene_dash_v2_core/advanced.dart';
import 'package:test/test.dart';

final class Position {
  double x;
  double y;
  Position(this.x, this.y);
}

final class Velocity {
  double x;
  double y;
  Velocity(this.x, this.y);
}

final class Player {
  const Player();
}

final class Frozen {
  const Frozen();
}

World _worldWithStores() {
  return World()
    ..stores.register<Position>(ObjectComponentStore<Position>())
    ..stores.register<Velocity>(ObjectComponentStore<Velocity>())
    ..stores.register<Player>(TagStore())
    ..stores.register<Frozen>(TagStore());
}

Entity _spawn(
  World world, {
  Position? position,
  Velocity? velocity,
  bool player = false,
  bool frozen = false,
}) {
  final entity = world.entities.spawn();
  if (position != null) world.insertNow<Position>(entity, position);
  if (velocity != null) world.insertNow<Velocity>(entity, velocity);
  if (player) world.insertNow<Player>(entity, const Player());
  if (frozen) world.insertNow<Frozen>(entity, const Frozen());
  return entity;
}

void main() {
  group('Query1', () {
    test('visits every entity with the component', () {
      final world = _worldWithStores();
      _spawn(world, position: Position(1, 1));
      _spawn(world, position: Position(2, 2));
      _spawn(world, velocity: Velocity(0, 0)); // no position

      final seen = <double>[];
      world.query1<Position>().each((entity, position) {
        seen.add(position.x);
      });
      expect(seen, unorderedEquals(<double>[1, 2]));
    });
  });

  group('Query2', () {
    test('matches only entities having both components', () {
      final world = _worldWithStores();
      final both = _spawn(
        world,
        position: Position(1, 1),
        velocity: Velocity(1, 0),
      );
      _spawn(world, position: Position(2, 2)); // no velocity
      _spawn(world, velocity: Velocity(9, 9)); // no position

      final matched = <Entity>[];
      world.query2<Position, Velocity>().each((entity, p, v) {
        matched.add(entity);
        p.x += v.x; // immediate field write through the object reference
      });

      expect(matched, <Entity>[both]);
      expect(world.stores.object<Position>().valueOf(both.index)!.x, 2);
    });

    test('applies requires (with) and excludes (without) filters', () {
      final world = _worldWithStores();
      final activePlayer = _spawn(
        world,
        position: Position(0, 0),
        velocity: Velocity(1, 1),
        player: true,
      );
      _spawn(
        world,
        position: Position(0, 0),
        velocity: Velocity(1, 1),
        player: true,
        frozen: true,
      ); // excluded by Frozen
      _spawn(
        world,
        position: Position(0, 0),
        velocity: Velocity(1, 1),
      ); // not a Player

      final matched = <Entity>[];
      world
          .query2<Position, Velocity>(
            withTypes: const [Player],
            withoutTypes: const [Frozen],
          )
          .each((entity, p, v) => matched.add(entity));

      expect(matched, <Entity>[activePlayer]);
    });

    test('chooses the smallest store as driver but yields correct matches', () {
      final world = _worldWithStores();
      // Many positions, few velocities: driver should be the velocity store.
      for (var i = 0; i < 50; i++) {
        _spawn(world, position: Position(i.toDouble(), 0));
      }
      final a = _spawn(
        world,
        position: Position(100, 0),
        velocity: Velocity(1, 0),
      );
      final b = _spawn(
        world,
        position: Position(200, 0),
        velocity: Velocity(2, 0),
      );

      final matched = <Entity>{};
      world.query2<Position, Velocity>().each((e, p, v) => matched.add(e));
      expect(matched, <Entity>{a, b});
    });
  });

  group('get (random access)', () {
    test('Query1.get returns the live component for a matching entity', () {
      final world = _worldWithStores();
      final e = _spawn(world, position: Position(3, 4));
      _spawn(world, position: Position(9, 9));

      final position = world.query1<Position>().get(e);
      expect(position, isNotNull);
      expect(position!.x, 3);

      // The returned object is live: mutating it writes through.
      position.x = 42;
      expect(world.stores.object<Position>().valueOf(e.index)!.x, 42);
    });

    test('Query1.get returns null when the entity lacks the component', () {
      final world = _worldWithStores();
      final e = _spawn(world, velocity: Velocity(1, 1)); // no Position
      expect(world.query1<Position>().get(e), isNull);
    });

    test('Query1.get returns null for a stale (reused) entity handle', () {
      final world = _worldWithStores();
      final e = _spawn(world, position: Position(1, 1));
      world.despawnNow(e);
      // Reusing the freed slot bumps the generation, so the old handle is stale.
      final reused = _spawn(world, position: Position(2, 2));
      expect(reused.index, e.index);
      expect(world.query1<Position>().get(e), isNull);
      expect(world.query1<Position>().get(reused)!.x, 2);
    });

    test('Query1.get honours with/without filters', () {
      final world = _worldWithStores();
      final frozen = _spawn(world, position: Position(1, 1), frozen: true);
      final active = _spawn(world, position: Position(2, 2), player: true);

      final players = world.query1<Position>(withTypes: const [Player]);
      expect(players.get(frozen), isNull); // not a Player
      expect(players.get(active), isNotNull);

      final unfrozen = world.query1<Position>(withoutTypes: const [Frozen]);
      expect(unfrozen.get(frozen), isNull); // excluded by Frozen
    });

    test('Query2.get invokes the callback with both components', () {
      final world = _worldWithStores();
      final e = _spawn(
        world,
        position: Position(1, 1),
        velocity: Velocity(5, 0),
      );
      _spawn(world, position: Position(2, 2)); // no velocity

      var calls = 0;
      final matched = world.query2<Position, Velocity>().get(e, (entity, p, v) {
        calls++;
        expect(entity, e);
        p.x += v.x; // write through
      });
      expect(matched, isTrue);
      expect(calls, 1);
      expect(world.stores.object<Position>().valueOf(e.index)!.x, 6);
    });

    test('Query2.get returns false without calling back when unmatched', () {
      final world = _worldWithStores();
      final e = _spawn(world, position: Position(1, 1)); // no velocity

      var called = false;
      final matched = world.query2<Position, Velocity>().get(
        e,
        (entity, p, v) => called = true,
      );
      expect(matched, isFalse);
      expect(called, isFalse);
    });
  });

  group('eachUntil', () {
    test('stops iterating as soon as the callback returns false', () {
      final world = _worldWithStores();
      for (var i = 0; i < 5; i++) {
        _spawn(world, position: Position(i.toDouble(), 0));
      }

      var visits = 0;
      world.query1<Position>().eachUntil((entity, position) {
        visits++;
        return visits < 3; // continue for two rows, stop on the third
      });
      expect(visits, 3);
    });

    test('visits every match when the callback keeps returning true', () {
      final world = _worldWithStores();
      _spawn(world, position: Position(1, 0));
      _spawn(world, position: Position(2, 0));

      final seen = <double>[];
      world.query1<Position>().eachUntil((entity, position) {
        seen.add(position.x);
        return true;
      });
      expect(seen, unorderedEquals(<double>[1, 2]));
    });

    test('respects with/without filters', () {
      final world = _worldWithStores();
      _spawn(world, position: Position(1, 0), player: true, frozen: true);
      final active = _spawn(world, position: Position(2, 0), player: true);

      final seen = <Entity>[];
      world
          .query1<Position>(
            withTypes: const [Player],
            withoutTypes: const [Frozen],
          )
          .eachUntil((entity, position) {
            seen.add(entity);
            return true;
          });
      expect(seen, <Entity>[active]);
    });

    test('is a no-op on an empty query', () {
      final world = _worldWithStores();
      _spawn(world, velocity: Velocity(1, 1)); // no Position

      var visits = 0;
      world.query1<Position>().eachUntil((entity, position) {
        visits++;
        return true;
      });
      expect(visits, 0);
    });

    test('Query2.eachUntil matches when the driver is not the first type '
        'argument', () {
      final world = _worldWithStores();
      // Many positions, one velocity: the Velocity store (B) must drive.
      for (var i = 0; i < 50; i++) {
        _spawn(world, position: Position(i.toDouble(), 0));
      }
      final both = _spawn(
        world,
        position: Position(100, 0),
        velocity: Velocity(1, 0),
      );

      final seen = <Entity>[];
      world.query2<Position, Velocity>().eachUntil((entity, p, v) {
        seen.add(entity);
        return true;
      });
      expect(seen, <Entity>[both]);
    });

    test('rejects structural mutation inside the callback', () {
      final world = _worldWithStores();
      _spawn(world, position: Position(0, 0));
      final extra = world.entities.spawn();

      expect(
        () => world.query1<Position>().eachUntil((entity, position) {
          world.insertNow<Position>(extra, Position(9, 9));
          return true;
        }),
        throwsA(isA<AssertionError>()),
      );
    });

    test('does not leave a query marked active after an early exit', () {
      final world = _worldWithStores();
      _spawn(world, position: Position(0, 0));
      world.query1<Position>().eachUntil((entity, position) => false);
      expect(() => _spawn(world, position: Position(1, 1)), returnsNormally);
    });
  });

  group('firstWhere / any', () {
    test('firstWhere returns the first row matching the predicate', () {
      final world = _worldWithStores();
      _spawn(world, position: Position(1, 0));
      final wanted = _spawn(world, position: Position(5, 0));

      final match = world.query1<Position>().firstWhere((entity, p) => p.x > 3);
      expect(match, isNotNull);
      expect(match!.$1, wanted);
      expect(match.$2.x, 5);
    });

    test('firstWhere returns null when nothing matches', () {
      final world = _worldWithStores();
      _spawn(world, position: Position(1, 0));
      expect(
        world.query1<Position>().firstWhere((entity, p) => p.x > 100),
        isNull,
      );
    });

    test('firstWhere stops scanning at the first match', () {
      final world = _worldWithStores();
      for (var i = 0; i < 5; i++) {
        _spawn(world, position: Position(i.toDouble(), 0));
      }

      var visits = 0;
      world.query1<Position>().firstWhere((entity, p) {
        visits++;
        return true; // every row matches: only the first may be visited
      });
      expect(visits, 1);
    });

    test('firstWhere respects filters', () {
      final world = _worldWithStores();
      _spawn(world, position: Position(1, 0), frozen: true);
      final active = _spawn(world, position: Position(2, 0));

      final match = world
          .query1<Position>(withoutTypes: const [Frozen])
          .firstWhere((entity, p) => true);
      expect(match!.$1, active);
    });

    test('Query2.firstWhere returns the full component record', () {
      final world = _worldWithStores();
      final e = _spawn(
        world,
        position: Position(1, 2),
        velocity: Velocity(3, 4),
      );

      final match = world.query2<Position, Velocity>().firstWhere(
        (entity, p, v) => v.x == 3,
      );
      expect(match, isNotNull);
      final (entity, p, v) = match!;
      expect(entity, e);
      expect(p.y, 2);
      expect(v.y, 4);
    });

    test('any reports whether a matching row satisfies the predicate', () {
      final world = _worldWithStores();
      _spawn(world, position: Position(1, 0));
      _spawn(world, position: Position(5, 0));

      final query = world.query1<Position>();
      expect(query.any((entity, p) => p.x > 3), isTrue);
      expect(query.any((entity, p) => p.x > 100), isFalse);
    });

    test('any stops at the first hit', () {
      final world = _worldWithStores();
      for (var i = 0; i < 5; i++) {
        _spawn(world, position: Position(i.toDouble(), 0));
      }

      var visits = 0;
      world.query1<Position>().any((entity, p) {
        visits++;
        return true;
      });
      expect(visits, 1);
    });

    test('any on an empty query is false', () {
      final world = _worldWithStores();
      expect(world.query1<Position>().any((entity, p) => true), isFalse);
    });
  });

  group('components (record accessor)', () {
    test('Query1.components returns a one-field record for a match', () {
      final world = _worldWithStores();
      final e = _spawn(world, position: Position(3, 4));

      final record = world.query1<Position>().components(e);
      expect(record, isNotNull);
      expect(record!.$1.x, 3);

      // The record field is the live component: mutating writes through.
      record.$1.x = 42;
      expect(world.get<Position>(e).x, 42);
    });

    test('Query2.components returns both components or null', () {
      final world = _worldWithStores();
      final both = _spawn(
        world,
        position: Position(1, 2),
        velocity: Velocity(3, 4),
      );
      final positionOnly = _spawn(world, position: Position(9, 9));

      final query = world.query2<Position, Velocity>();
      final record = query.components(both);
      expect(record, isNotNull);
      final (p, v) = record!;
      expect(p.y, 2);
      expect(v.x, 3);

      expect(query.components(positionOnly), isNull);
    });

    test('components is null for stale handles and filtered-out entities', () {
      final world = _worldWithStores();
      final frozen = _spawn(world, position: Position(1, 1), frozen: true);
      final dead = _spawn(world, position: Position(2, 2));
      world.despawnNow(dead);

      expect(
        world.query1<Position>(withoutTypes: const [Frozen]).components(frozen),
        isNull,
      );
      expect(world.query1<Position>().components(dead), isNull);
    });

    test('components is null when the entity misses a later component', () {
      final world = _worldWithStores();
      final e = _spawn(world, velocity: Velocity(1, 1)); // no Position
      expect(world.query2<Velocity, Position>().components(e), isNull);
      expect(world.query2<Position, Velocity>().components(e), isNull);
    });
  });

  group('debug guards', () {
    test('rejects structural mutation while a query iterates', () {
      final world = _worldWithStores();
      _spawn(world, position: Position(0, 0));
      final extra = world.entities.spawn();

      expect(
        () => world.query1<Position>().each((entity, position) {
          world.insertNow<Position>(extra, Position(9, 9));
        }),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
