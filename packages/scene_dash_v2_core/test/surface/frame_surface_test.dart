import 'package:scene_dash_v2_core/advanced.dart';
import 'package:test/test.dart';

enum Act { jump, fire }

final class Ping {
  const Ping(this.n);
  final int n;
}

final class Health {
  Health(this.value);
  double value;
}

final class Frozen implements Tag {
  const Frozen();
}

base class Shape {
  const Shape();
}

final class Circle extends Shape {
  const Circle();
}

final class Square extends Shape {
  const Square();
}

void main() {
  test('cached time resources follow a replaced resource', () {
    final game = TestGame.headless()..start();
    game.pump(dt: 0.01);
    expect(game.world.delta, closeTo(0.01, 1e-12));
    final replacement = FrameTime()..delta = 0.5;
    game.world.resources.insert<FrameTime>(replacement);
    expect(identical(game.world.frameTime, replacement), isTrue);
    expect(game.world.delta, 0.5);
  });

  test('fixed alpha carries the leftover fraction of a step', () {
    final game = TestGame.headless(fixedDt: 0.25)..start();
    game.pump(dt: 0.375);
    expect(game.world.fixedTime.alpha, closeTo(0.5, 1e-9));
    game.pump(dt: 0.125);
    expect(game.world.fixedTime.alpha, closeTo(0, 1e-9));
  });

  test('eachEvent reads each event once', () {
    final seen = <int>[];
    final game = TestGame.headless(
      features: [
        (game) => game.addSystem(
          Schedules.update,
          (world) => world.eachEvent<Ping>((ping) => seen.add(ping.n)),
          label: 'read',
        ),
      ],
    )..start();
    game
      ..emit(const Ping(1))
      ..emit(const Ping(2))
      ..pump()
      ..pump();
    expect(seen, [1, 2]);
  });

  test('justPressed and justReleased hold for exactly one frame', () {
    final log = <String>[];
    final game = TestGame.headless(
      features: [
        (game) => game.addSystem(Schedules.update, (world) {
          final buttons = world.buttons<Act>();
          if (buttons.justPressed(Act.jump)) log.add('down');
          if (buttons.justReleased(Act.jump)) log.add('up');
        }, label: 'edges'),
      ],
    )..start();
    game.press(Act.jump);
    game.pump();
    game.pump();
    game.release(Act.jump);
    game.pump();
    game.pump();
    game
      ..press(Act.jump)
      ..release(Act.jump)
      ..pump();
    expect(log, ['down', 'up', 'down', 'up']);
  });

  test('fixed systems see each edge in exactly one step', () {
    var stepEdges = 0;
    var frameEdges = 0;
    final game = TestGame.headless(
      fixedDt: 0.25,
      features: [
        (game) => game
          ..addSystem(Schedules.fixedUpdate, (world) {
            if (world.buttons<Act>().justPressed(Act.fire)) stepEdges++;
          }, label: 'step')
          ..addSystem(Schedules.update, (world) {
            if (world.buttons<Act>().justPressed(Act.fire)) frameEdges++;
          }, label: 'frame'),
      ],
    )..start();
    game.press(Act.fire);
    game.pump(dt: 0.125);
    expect((stepEdges, frameEdges), (0, 1));
    game.pump(dt: 0.5);
    expect((stepEdges, frameEdges), (1, 1));
    game.pump(dt: 0.5);
    expect((stepEdges, frameEdges), (1, 1));
  });

  group('group', () {
    test('shares runIf and inSet with its systems', () {
      const phase = SystemSet('phase');
      var enabled = false;
      final ran = <String>[];
      final game = TestGame.headless(
        features: [
          (game) => game.group(runIf: (_) => enabled, inSet: phase, (game) {
            game.addSystem(Schedules.update, (_) => ran.add('a'), label: 'a');
            game.group(runIf: (_) => ran.length < 2, (game) {
              game.addSystem(
                Schedules.update,
                (_) => ran.add('b'),
                label: 'b',
                inSet: phase,
              );
            });
          }),
        ],
      )..start();
      game.pump();
      expect(ran, isEmpty);
      enabled = true;
      game.pump();
      expect(ran, ['a', 'b']);
      game.pump();
      expect(ran, ['a', 'b', 'a']);
    });

    test('rejects a conflicting set', () {
      expect(
        () => TestGame.headless(
          features: [
            (game) => game.group(inSet: const SystemSet('x'), (game) {
              game.addSystem(
                Schedules.update,
                (_) {},
                label: 'y',
                inSet: const SystemSet('y'),
              );
            }),
          ],
        ),
        throwsArgumentError,
      );
    });

    test('ordering edges resolve across groups', () {
      final ran = <String>[];
      void first(World world) => ran.add('first');
      void second(World world) => ran.add('second');
      final game = TestGame.headless(
        features: [
          (game) => game.group((game) {
            game.addSystem(Schedules.update, second, after: [first]);
          }),
          (game) => game.addSystem(Schedules.update, first),
        ],
      )..start();
      game.pump();
      expect(ran, ['first', 'second']);
    });
  });

  group('addSystems', () {
    void first(World world) => world.resource<List<String>>().add('first');
    void second(World world) => world.resource<List<String>>().add('second');
    void third(World world) => world.resource<List<String>>().add('third');

    TestGame boot({required bool chain, bool Function()? gate}) =>
        TestGame.headless(
          strictAccess: true,
          features: [
            (game) {
              game.world.insert<List<String>>(<String>[]);
              game.addSystems(
                Schedules.update,
                [
                  SystemEntry(third, writes: {Health}),
                  SystemEntry(second, writes: {Health}),
                  SystemEntry(first, reads: {Health}),
                ],
                runIf: gate == null ? null : (_) => gate(),
                chain: chain,
              );
            },
          ],
        )..start();

    test('chain runs entries in list order', () {
      final game = boot(chain: true)..pump();
      expect(game.world.resource<List<String>>(), ['third', 'second', 'first']);
    });

    test('shares runIf across entries', () {
      var open = false;
      final game = boot(chain: true, gate: () => open)..pump();
      expect(game.world.resource<List<String>>(), isEmpty);
      open = true;
      game.pump();
      expect(game.world.resource<List<String>>(), hasLength(3));
    });

    test('conflict checks see each entry access', () {
      expect(
        () => boot(chain: false),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('Health'),
          ),
        ),
      );
    });
  });

  test('an unnamed system is reported once, a labeled one never', () {
    final messages = <String>[];
    TestGame.headless(
      onDiagnostic: messages.add,
      features: [
        (game) => game
          ..addSystem(Schedules.update, (_) {}, label: 'named')
          ..addSystem(Schedules.update, (_) {})
          ..addSystem(Schedules.update, (_) {}),
      ],
    );
    expect(messages.where((m) => m.contains('label:')), hasLength(1));
  });

  group('ComponentHandle', () {
    test('reads, checks and throws like get/tryGet/has', () {
      final game = TestGame.headless()..start();
      final world = game.world;
      final hurt = world.spawn([Health(3), const Frozen()]);
      final bare = world.spawn(<Object>[]);
      game.pump();
      final health = world.handle<Health>();
      final frozen = world.handle<Frozen>();
      expect(health.of(hurt)?.value, 3);
      expect(health.of(bare), isNull);
      expect(health.has(hurt), isTrue);
      expect(frozen.has(hurt), isTrue);
      expect(frozen.has(bare), isFalse);
      expect(() => health.get(bare), throwsStateError);
      world.despawn(hurt);
      game.pump();
      expect(health.of(hurt), isNull);
      expect(health.has(hurt), isFalse);
    });

    test('reads a subtype from its supertype store', () {
      final game = TestGame.headless()..start();
      final world = game.world..ensureStore<Shape>();
      final circle = world.spawn([const Circle()]);
      game.pump();
      expect(world.handle<Circle>().of(circle), isA<Circle>());
      expect(world.handle<Shape>().has(circle), isTrue);
    });
  });

  group('store split', () {
    test('asserts when a subtype gets its own store too late', () {
      final game = TestGame.headless()..start();
      final world = game.world..ensureStore<Shape>();
      world.spawn([const Circle()]);
      game.pump();
      expect(
        () => world.query<Circle>().count(),
        throwsA(isA<AssertionError>()),
      );
    });

    test('asserts when a supertype store arrives after a subtype store', () {
      final game = TestGame.headless()..start();
      final world = game.world..ensureStore<Square>();
      world.spawn([const Square()]);
      game.pump();
      expect(
        () => world.query<Shape>().count(),
        throwsA(isA<AssertionError>()),
      );
    });

    test('asserts when both stores would exist before any spawn', () {
      final game = TestGame.headless()..start();
      final world = game.world;
      world.query<Shape>().count();
      expect(
        () => world.query<Circle>().count(),
        throwsA(isA<AssertionError>()),
      );
    });

    test('reading a subtype through its supertype store stays quiet', () {
      final game = TestGame.headless()..start();
      final world = game.world..ensureStore<Shape>();
      final square = world.spawn([const Square()]);
      game.pump();
      expect(world.tryGet<Circle>(square), isNull);
      expect(world.has<Square>(square), isTrue);
      expect(world.handle<Square>().of(square), isA<Square>());
    });

    test('add with a subtype keeps it in the supertype store', () {
      final game = TestGame.headless()..start();
      final world = game.world..ensureStore<Shape>();
      final entity = world.spawn([Health(1)]);
      game.pump();
      world.add(entity, const Circle());
      game.pump();
      expect(world.stores.isRegistered(Circle), isFalse);
      expect(world.query<Shape>().count(), 1);
      expect(world.has<Circle>(entity), isTrue);
    });

    test('having and without filter subtypes through the supertype store', () {
      final game = TestGame.headless()..start();
      final world = game.world..ensureStore<Shape>();
      final round = world.spawn([Health(1), const Circle()]);
      final boxy = world.spawn([Health(2), const Square()]);
      world.spawn([Health(3)]);
      game.pump();
      expect(world.query<Health>().having<Circle>().count(), 1);
      expect(world.query<Health>().having<Circle>().first.$1, round);
      expect(world.query<Health>().having<Square>().first.$1, boxy);
      expect(world.query<Health>().without<Circle>().count(), 2);
      expect(world.entitiesWith<Circle>().firstOrNull, round);
      expect(world.entitiesWith<Square>().count(), 1);
      expect(world.stores.isRegistered(Circle), isFalse);
      expect(world.stores.isRegistered(Square), isFalse);
    });
  });
}
