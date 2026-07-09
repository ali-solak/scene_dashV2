import 'package:scene_dash_v2_core/advanced.dart';
import 'package:test/test.dart';

final class Position {
  double x;
  double y;
  Position(this.x, this.y);
}

final class Player {
  const Player();
}

World _worldWithStores() {
  return World()
    ..stores.register<Position>(ObjectComponentStore<Position>())
    ..stores.register<Player>(TagStore());
}

Entity _spawn(World world, {Position? position, bool player = false}) {
  final entity = world.entities.spawn();
  if (position != null) world.insertNow<Position>(entity, position);
  if (player) world.insertNow<Player>(entity, const Player());
  return entity;
}

void main() {
  group('Query1.isEmpty', () {
    test('is true with no matches and false with at least one', () {
      final world = _worldWithStores();
      expect(world.query1<Position>().isEmpty, isTrue);
      _spawn(world, position: Position(1, 1));
      expect(world.query1<Position>().isEmpty, isFalse);
    });

    test('honours filters', () {
      final world = _worldWithStores();
      _spawn(world, position: Position(1, 1)); // not a Player
      final players = world.query1<Position>(withTypes: const [Player]);
      expect(players.isEmpty, isTrue);
      _spawn(world, position: Position(2, 2), player: true);
      expect(players.isEmpty, isFalse);
    });
  });

  group('Query1.singleOrNull / single', () {
    test('singleOrNull returns null when there are no matches', () {
      final world = _worldWithStores();
      expect(world.query1<Position>().singleOrNull(), isNull);
    });

    test('returns the one match as (entity, value)', () {
      final world = _worldWithStores();
      final e = _spawn(world, position: Position(3, 4));
      final match = world.query1<Position>().single();
      expect(match.$1, e);
      expect(match.$2.x, 3);
    });

    test('single throws when there are no matches', () {
      final world = _worldWithStores();
      expect(
        () => world.query1<Position>().single(),
        throwsA(isA<StateError>()),
      );
    });

    test('throws when more than one entity matches', () {
      final world = _worldWithStores();
      _spawn(world, position: Position(1, 1));
      _spawn(world, position: Position(2, 2));
      expect(
        () => world.query1<Position>().singleOrNull(),
        throwsA(isA<StateError>()),
      );
      expect(
        () => world.query1<Position>().single(),
        throwsA(isA<StateError>()),
      );
    });

    test('does not leave a query marked active after resolving', () {
      final world = _worldWithStores();
      _spawn(world, position: Position(1, 1));
      world.query1<Position>().single();
      // A structural change afterwards must not trip the active-query guard.
      expect(() => _spawn(world, position: Position(2, 2)), returnsNormally);
    });
  });

  group('Single<A>', () {
    test('exposes the one entity and value', () {
      final world = _worldWithStores();
      final e = _spawn(world, position: Position(5, 6), player: true);
      final single = Single<Position>(
        world.query1<Position>(withTypes: const [Player]),
      );
      expect(single.entity, e);
      expect(single.value.x, 5);
    });

    test('throws when zero or multiple match', () {
      final world = _worldWithStores();
      final single = Single<Position>(world.query1<Position>());
      expect(() => single.value, throwsA(isA<StateError>()));
      _spawn(world, position: Position(1, 1));
      _spawn(world, position: Position(2, 2));
      // A failed resolution is not cached, so the next access re-walks the
      // query and reports the new failure mode.
      expect(() => single.value, throwsA(isA<StateError>()));
    });

    test('caches the resolution until beginRun', () {
      final world = _worldWithStores();
      final first = _spawn(world, position: Position(1, 1));
      final single = Single<Position>(world.query1<Position>());
      expect(single.entity, first);

      // The match set changes, but the cached resolution stays stable —
      // that is the per-run contract.
      world.removeNow<Position>(first);
      final second = _spawn(world, position: Position(2, 2));
      expect(single.entity, first, reason: 'cached within the run');

      single.beginRun();
      expect(single.entity, second, reason: 're-resolved on the next run');
    });
  });

  group('OptionalSingle<A>', () {
    test('valueOrNull is null when none match, value when one matches', () {
      final world = _worldWithStores();
      final opt = OptionalSingle<Position>(world.query1<Position>());
      expect(opt.isPresent, isFalse);
      expect(opt.valueOrNull, isNull);
      _spawn(world, position: Position(7, 8));
      opt.beginRun(); // new run: the absent resolution was cached
      expect(opt.isPresent, isTrue);
      expect(opt.valueOrNull!.x, 7);
    });

    test('still throws when more than one matches', () {
      final world = _worldWithStores();
      _spawn(world, position: Position(1, 1));
      _spawn(world, position: Position(2, 2));
      final opt = OptionalSingle<Position>(world.query1<Position>());
      expect(() => opt.valueOrNull, throwsA(isA<StateError>()));
      expect(
        () => opt.isPresent,
        throwsA(isA<StateError>()),
        reason: 'isPresent shares the validated resolution',
      );
    });

    test('caches the resolution until beginRun', () {
      final world = _worldWithStores();
      final opt = OptionalSingle<Position>(world.query1<Position>());
      expect(opt.isPresent, isFalse);

      _spawn(world, position: Position(3, 4));
      expect(opt.isPresent, isFalse, reason: 'absent is cached within the run');
      expect(opt.valueOrNull, isNull);

      opt.beginRun();
      expect(opt.isPresent, isTrue);
      expect(opt.valueOrNull!.x, 3);
    });
  });
}
