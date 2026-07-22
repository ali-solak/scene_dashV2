import 'package:scene_dash_v2_core/scene_dash_v2_core.dart';
import 'package:test/test.dart';

final class Position {
  double x;
  Position(this.x);
}

final class Velocity {
  final double dx;
  const Velocity(this.dx);
}

final class Unclaimed {
  final int value;
  Unclaimed(this.value);
}

final class Marker implements Tag {}

final class Ping {
  final int n;
  const Ping(this.n);
}

enum RunMode { title, playing }

void main() {
  group('addSystem', () {
    test('systems are stateless functions run in schedule; ordering edges '
        'are by function reference', () {
      final log = <String>[];
      void first(World world) => log.add('first');
      void second(World world) => log.add('second');
      final game = TestGame.headless(
        features: [
          (game) {
            game.addSystem(Schedules.update, second, reads: const {});
            // Registered later, ordered earlier.
            game.addSystem(
              Schedules.update,
              first,
              reads: const {},
              before: [second],
            );
          },
        ],
      );
      game.pump();
      expect(log, ['first', 'second']);
    });

    test('an ordering edge to an unregistered function fails loudly', () {
      void a(World world) {}
      void b(World world) {}
      expect(
        () => TestGame.headless(
          features: [
            (game) => game.addSystem(Schedules.update, a, after: [b]),
          ],
        ),
        throwsA(
          isA<StateError>().having((e) => e.message, 'message', contains('b')),
        ),
      );
    });

    test('runIf gates on the carried conditions (inState)', () {
      var runs = 0;
      final game = TestGame.headless(
        features: [
          (game) {
            game.addState(RunMode.title);
            game.addSystem(
              Schedules.update,
              (world) => runs++,
              runIf: inState(RunMode.playing),
            );
          },
        ],
      );
      game.pump();
      expect(runs, 0);
      game.world.setState(RunMode.playing);
      game.pump();
      expect(runs, 1);
      expect(game.world.state<RunMode>(), RunMode.playing);
    });

    test('strictAccess rejects an undeclared system with guidance', () {
      void undeclared(World world) {}
      expect(
        () => TestGame.headless(
          strictAccess: true,
          features: [(game) => game.addSystem(Schedules.update, undeclared)],
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(contains('undeclared'), contains('strictAccess')),
          ),
        ),
      );
    });

    test('declared writes feed the conflict detector; undeclared systems '
        'are excluded', () {
      void writerA(World world) {}
      void writerB(World world) {}
      void undeclared(World world) {}
      // Two unordered writers of the same type: boot throws (policy error).
      expect(
        () => TestGame.headless(
          features: [
            (game) {
              game
                ..addSystem(Schedules.update, writerA, writes: {Position})
                ..addSystem(Schedules.update, writerB, writes: {Position});
            },
          ],
        ).start(),
        throwsStateError,
      );
      // The same pair with one undeclared: excluded, no conflict.
      TestGame.headless(
        features: [
          (game) {
            game
              ..addSystem(Schedules.update, writerA, writes: {Position})
              ..addSystem(Schedules.update, undeclared);
          },
        ],
      ).start();
    });

    test('debug drift check: a query naming an undeclared type reports '
        'once', () {
      final diagnostics = <String>[];
      void drifting(World world) {
        world.query<Velocity>();
      }

      final game = TestGame.headless(
        onDiagnostic: diagnostics.add,
        features: [
          (game) =>
              game.addSystem(Schedules.update, drifting, reads: {Position}),
        ],
      );
      game.pump();
      game.pump();
      expect(
        diagnostics.where(
          (d) => d.contains('Access drift') && d.contains('Velocity'),
        ),
        hasLength(1),
      );
    });
  });

  group('events', () {
    test('world.events<T>() keeps one cursor per registration: every '
        'event exactly once, across the fixed loop', () {
      final seenA = <int>[];
      final seenB = <int>[];
      void readerA(World world) {
        for (final ping in world.events<Ping>()) {
          seenA.add(ping.n);
        }
      }

      void readerB(World world) {
        for (final ping in world.events<Ping>()) {
          seenB.add(ping.n);
        }
      }

      final game = TestGame.headless(
        fixedDt: 1 / 64,
        features: [
          (game) {
            game
              ..addSystem(Schedules.fixedUpdate, readerA)
              ..addSystem(Schedules.update, readerB);
          },
        ],
      );
      game.start();
      game
        ..emit(const Ping(1))
        ..emit(const Ping(2));
      // Two fixed steps this frame: the fixed reader sees each event once.
      game.pump(dt: 2 / 64);
      expect(seenA, [1, 2]);
      expect(seenB, [1, 2], reason: 'independent cursor, same events');
      game.pump(dt: 2 / 64);
      expect(seenA, [1, 2], reason: 'nothing new, nothing re-read');
    });

    test('world.consumeAny<T>() reports pending events and drains the '
        'cursor', () {
      final results = <bool>[];
      void reader(World world) {
        results.add(world.consumeAny<Ping>());
      }

      final game = TestGame.headless(
        features: [(game) => game.addSystem(Schedules.update, reader)],
      );
      game.start();
      game.pump(); // First run registers the cursor: nothing pending.
      expect(results, [false]);

      game
        ..emit(const Ping(1))
        ..emit(const Ping(2));
      game.pump();
      expect(results, [false, true]);

      game.pump();
      expect(results, [
        false,
        true,
        false,
      ], reason: 'consumed: the cursor moved past both events');
    });

    test('a system can emit for a later system in the same frame', () {
      final relayed = <int>[];
      void producer(World world) {
        for (final ping in world.events<Ping>()) {
          world.emit(Ping(ping.n * 10));
        }
      }

      void consumer(World world) {
        for (final ping in world.events<Ping>()) {
          relayed.add(ping.n);
        }
      }

      final game = TestGame.headless(
        features: [
          (game) {
            game
              ..addSystem(Schedules.fixedUpdate, producer)
              ..addSystem(Schedules.update, consumer);
          },
        ],
      );
      game.start();
      game.emit(const Ping(1));
      game.pumpFixed(steps: 1);
      expect(relayed, [1, 10]);
    });

    test('events<T>() outside a running system throws with the rule', () {
      final game = TestGame.headless();
      game.pump();
      expect(
        () => game.world.events<Ping>(),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('outside a running system'),
          ),
        ),
      );
    });
  });

  group('spawning', () {
    test('spawn lists apply at the boundary; parked parts materialize at '
        'the first typed use and age out loudly', () {
      final diagnostics = <String>[];
      final game = TestGame.headless(onDiagnostic: diagnostics.add);
      final entity = game.world.spawn([Position(1), Unclaimed(7)]);
      game.pump();
      // Position was registered by nothing yet either — both parked until
      // a typed site names them.
      expect(game.world.query<Position>().single.$2.x, 1);
      expect(game.world.stores.isRegistered(Unclaimed), isFalse);
      game.pump();
      game.pump();
      expect(
        diagnostics.where(
          (d) => d.contains('Unclaimed') && d.contains('parked'),
        ),
        hasLength(1),
      );
      expect(game.world.query<Unclaimed>().single.$2.value, 7);
      expect(game.world.get<Unclaimed>(entity).value, 7);
    });

    test('unregistered tags in a spawn list fail with registerTag '
        'guidance; registered ones insert', () {
      final game = TestGame.headless();
      game.world.spawn([Marker()]);
      expect(
        game.start,
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(contains('Marker'), contains('registerTag')),
          ),
        ),
      );

      final game2 = TestGame.headless(
        features: [(game) => game.registerTag<Marker>()],
      );
      final tagged = game2.world.spawn([Marker(), Position(0)]);
      game2.pump();
      expect(game2.world.has<Marker>(tagged), isTrue);
      expect(game2.world.query<Position>(require: [Marker]).count(), 1);
    });

    test('ownedBy despawns subtrees in one boundary, chains included', () {
      final game = TestGame.headless(
        features: [(game) => game.registerComponent<Position>()],
      );
      final owner = game.world.spawn([Position(0)]);
      final weapon = game.world.spawn([Position(1)], ownedBy: owner);
      final trail = game.world.spawn([Position(2)], ownedBy: weapon);
      game.pump();
      game.world.despawn(owner);
      game.pump();
      expect(game.world.isAlive(weapon), isFalse);
      expect(game.world.isAlive(trail), isFalse);
      expect(game.world.entities.aliveCount, 0);
    });

    test('World.reset drops pending spawns safely', () {
      final game = TestGame.headless(
        features: [(game) => game.registerComponent<Position>()],
      );
      game.world.spawn([Position(0)]);
      game.start();
      game.world.spawn([Position(1)]); // pending
      game.world.reset();
      game.pump();
      expect(game.world.query<Position>().count(), 0);
    });
  });

  group('states', () {
    test('OnEnter/OnExit registration + DespawnOnExit scoping through the '
        'sugar', () {
      final log = <String>[];
      final game = TestGame.headless(
        features: [
          (game) {
            game
              ..registerComponent<Position>()
              ..addState(RunMode.playing)
              ..addSystem(OnEnter(RunMode.playing), (w) => log.add('enter'))
              ..addSystem(OnExit(RunMode.playing), (w) => log.add('exit'));
          },
        ],
      );
      final scoped = game.world.spawn([
        Position(0),
        const DespawnOnExit(RunMode.playing),
      ]);
      game.pump();
      expect(log, ['enter']);
      expect(game.world.isAlive(scoped), isTrue);
      game.world.setState(RunMode.title);
      game.pump();
      expect(log, ['enter', 'exit']);
      expect(game.world.isAlive(scoped), isFalse);
    });

    test('hasResource gates a system on an optional capability', () {
      final log = <String>[];
      final game = TestGame.headless(
        features: [
          (game) => game.addSystem(
            Schedules.update,
            (w) => log.add('ran'),
            reads: const {},
            runIf: hasResource<_Capability>(),
          ),
        ],
      );
      game.pump();
      expect(log, isEmpty, reason: 'resource absent: the system is skipped');
      game.world.insert(_Capability());
      game.pump();
      expect(log, ['ran'], reason: 'resource present: runs from then on');
    });
  });
}

final class _Capability {}
