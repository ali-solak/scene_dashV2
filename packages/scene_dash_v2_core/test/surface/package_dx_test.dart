import 'package:scene_dash_v2_core/scene_dash_v2_core.dart';
import 'package:test/test.dart';

class Position {
  Position(this.x);
  int x;
}

final class SpecialPosition extends Position {
  SpecialPosition(super.x);
}

final class Unclaimed {}

final class Velocity {}

final class Health {}

final class Armor {}

void main() {
  test('typed use claims newly parked subtypes after earlier query misses', () {
    final game = TestGame.headless();
    game.world.spawn([Unclaimed()]);
    game.start();
    expect(game.world.query<Position>().count(), 0);
    expect(game.world.query<Position>().count(), 0);
    final entity = game.world.spawn([SpecialPosition(7)]);
    game.pump();
    expect(game.world.query<Position>().single.$2.x, 7);
    game.world.despawn(entity);
    game.pump();
    expect(game.world.query<Position>().count(), 0);
    game.world.spawn([SpecialPosition(8)]);
    game.pump();
    expect(game.world.query<Position>().single.$2.x, 8);
  });

  test('explicit registration claims waiting parts and reset drops them', () {
    final game = TestGame.headless();
    final entity = game.world.spawn([SpecialPosition(4)]);
    game.start();
    game.builder.registerComponent<Position>();
    expect(game.world.get<Position>(entity).x, 4);
    game.world.spawn([Unclaimed()]);
    game.pump();
    game.world.reset();
    game.world.spawn([SpecialPosition(9)]);
    game.pump();
    expect(game.world.query<Unclaimed>().count(), 0);
    expect(game.world.query<Position>().single.$2.x, 9);
  });

  test('aged diagnostics report new types without repeating old ones', () {
    final messages = <String>[];
    final game = TestGame.headless(onDiagnostic: messages.add);
    game.world.spawn([Unclaimed()]);
    game.pumpFixed(steps: 4);
    expect(messages, hasLength(1));
    game.world.spawn([Unclaimed(), SpecialPosition(0)]);
    game.pumpFixed(steps: 4);
    expect(messages, hasLength(2));
    expect(messages.last, contains('SpecialPosition'));
  });

  for (final reverse in [false, true]) {
    test('forward ordering across features, reverse installation=$reverse', () {
      final log = <int>[];
      void first(World w) => log.add(1);
      void second(World w) => log.add(2);
      void third(World w) => log.add(3);
      final edges = <WorldSystem>[second];
      final features = <Feature>[
        (g) => g.addSystem(Schedules.update, first, before: edges),
        (g) => g.addSystem(Schedules.update, third, after: [second]),
        (g) => g.addSystem(Schedules.update, second, label: 'middle'),
      ];
      final game = TestGame.headless(
        features: reverse ? features.reversed.toList() : features,
      );
      edges.clear(); // Registration owns a snapshot of the caller's list.
      game.pump();
      expect(log, [1, 2, 3]);
    });
  }

  test(
    'forward independentOf suppresses conflicts after both features install',
    () {
      void first(World w) {}
      void second(World w) {}
      final game = TestGame.headless(
        features: [
          (g) => g.addSystem(
            Schedules.update,
            first,
            writes: {Position},
            independentOf: [second],
          ),
          (g) => g.addSystem(Schedules.update, second, writes: {Position}),
        ],
      );
      game.start();
      expect(game.app.accessConflicts, isEmpty);
    },
  );

  for (final edge in ['before', 'after', 'independentOf']) {
    test(
      '$edge rejects another schedule even with conflict checks disabled',
      () {
        void first(World w) {}
        void second(World w) {}
        final game = TestGame.headless(
          accessConflictPolicy: AccessConflictPolicy.ignore,
          features: [
            (g) => g.addSystem(
              Schedules.update,
              first,
              before: edge == 'before' ? [second] : [],
              after: edge == 'after' ? [second] : [],
              independentOf: edge == 'independentOf' ? [second] : [],
            ),
            (g) =>
                g.addSystem(Schedules.fixedUpdate, second, label: 'late-label'),
          ],
        );
        expect(
          game.start,
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'guidance',
              allOf(
                contains('late-label'),
                contains('update'),
                contains('Register both systems'),
              ),
            ),
          ),
        );
      },
    );
  }

  test('forward reference cycles retain explicit labels in the error', () {
    void first(World w) {}
    void second(World w) {}
    final game = TestGame.headless(
      features: [
        (g) => g
          ..addSystem(Schedules.update, first, after: [second], label: 'first')
          ..addSystem(
            Schedules.update,
            second,
            after: [first],
            label: 'second',
          ),
      ],
    );
    expect(
      game.start,
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'cycle',
          allOf(contains('cycle'), contains('first'), contains('second')),
        ),
      ),
    );
  });

  test(
    'all snapshot arities freeze membership but share component references',
    () {
      final game = TestGame.headless();
      final position = Position(1);
      game.world.spawn([position, Velocity(), Health(), Armor()]);
      game.start();
      final w = game.world;
      final one = w.query<Position>().snapshot();
      final two = w.query2<Position, Velocity>().snapshot();
      final three = w.query3<Position, Velocity, Health>().snapshot();
      final four = w.query4<Position, Velocity, Health, Armor>().snapshot();
      expect(w.query<Position>().records, one);
      expect(w.query2<Position, Velocity>().records, two);
      expect(w.query3<Position, Velocity, Health>().records, three);
      expect(w.query4<Position, Velocity, Health, Armor>().records, four);
      position.x = 5;
      w.despawn(one.single.$1);
      w.spawn([Position(2), Velocity(), Health(), Armor()]);
      game.pump();
      for (final snapshot in [one, two, three, four]) {
        expect(snapshot, hasLength(1));
      }
      expect(one.single.$2.x, 5);
      expect(two.single.$2, same(position));
      expect(three.single.$2, same(position));
      expect(four.single.$2, same(position));
      expect(w.query<Position>().snapshot().single.$2.x, 2);
      one.clear();
      expect(w.query<Position>().count(), 1);
    },
  );
}
