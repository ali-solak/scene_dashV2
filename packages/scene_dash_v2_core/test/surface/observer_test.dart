import 'package:scene_dash_v2_core/advanced.dart' hide ClassicWorldQueries;
import 'package:scene_dash_v2_core/scene_dash_v2_core.dart';
import 'package:test/test.dart';

// Test vocabulary: a valued component, a reaction component observers
// attach, a tag, and an event.
final class Health {
  final int amount;
  Health(this.amount);
}

final class Sparkle {
  const Sparkle();
}

final class Burning implements Tag {
  const Burning();
}

final class Ping {
  const Ping();
}

void main() {
  group('component observers (S1-S6)', () {
    test('fire during the flush, not at enqueue (S1)', () {
      final log = <String>[];
      final game = TestGame.headless(
        features: [
          (g) => g
            ..registerComponent<Health>()
            ..observe<Health>(
              onAdd: (world, entity, health) => log.add('add:${health.amount}'),
              onRemove: (world, entity, health) =>
                  log.add('remove:${health.amount}'),
            ),
        ],
      );
      game.start();
      final entity = game.world.spawn(<Object>[]);
      game.pump();

      game.world.add(entity, Health(7));
      expect(log, isEmpty, reason: 'the add is deferred; nothing applied yet');
      game.pump();
      expect(log, ['add:7'], reason: 'fired at the command boundary');

      game.world.remove<Health>(entity);
      expect(log, ['add:7'], reason: 'the remove is deferred too');
      game.pump();
      expect(log, ['add:7', 'remove:7']);
    });

    test('multiple observers per type fire in registration order (S2)', () {
      final log = <String>[];
      final world = World();
      final registry = ObserverRegistry.of(world);
      registry.observe<Health>(onAdd: (w, e, h) => log.add('first'));
      registry.observe<Health>(onAdd: (w, e, h) => log.add('second'));

      world.spawn([Health(1)]);
      SpawnQueue.of(world).flush();
      expect(log, ['first', 'second']);
    });

    test('despawn strips components and fires onRemove with the live '
        'instance (S3)', () {
      Health? removed;
      final game = TestGame.headless(
        features: [
          (g) => g
            ..registerComponent<Health>()
            ..observe<Health>(
              onRemove: (world, entity, health) => removed = health,
            ),
        ],
      );
      game.start();
      final entity = game.world.spawn([Health(42)]);
      game.pump();

      game.world.despawn(entity);
      game.pump();
      expect(removed?.amount, 42);
      expect(game.world.isAlive(entity), isFalse);
    });

    test('add-over-existing replaces the value and fires nothing (S4)', () {
      var adds = 0;
      final game = TestGame.headless(
        features: [
          (g) => g
            ..registerComponent<Health>()
            ..observe<Health>(onAdd: (world, entity, health) => adds++),
        ],
      );
      game.start();
      final entity = game.world.spawn([Health(1)]);
      game.pump();
      expect(adds, 1);

      game.world.add(entity, Health(2));
      game.pump();
      expect(adds, 1, reason: 'absent→present only');
      expect(game.world.get<Health>(entity).amount, 2, reason: 'value swapped');
    });

    test('observer-enqueued deferred verbs land in the same flush (S5)', () {
      final world = World();
      ObserverRegistry.of(world)
        ..observe<Health>(
          onAdd: (w, entity, health) => w.add(entity, const Sparkle()),
        )
        ..observe<Sparkle>(
          onAdd: (w, entity, sparkle) => w.remove<Health>(entity),
        );

      final entity = world.spawn([Health(1)]);
      SpawnQueue.of(world).flush();

      // One flush settled the whole cascade: Health applied → Sparkle added
      // (same flush) → Health removed again (same flush).
      expect(world.has<Sparkle>(entity), isTrue);
      expect(world.has<Health>(entity), isFalse);
    });

    test('world.events<T>() inside an observer throws the rule (S5)', () {
      final game = TestGame.headless(
        features: [
          (g) => g
            ..registerComponent<Health>()
            ..observe<Health>(
              onAdd: (world, entity, health) => world.events<Ping>(),
            ),
        ],
      );
      game.start();
      game.world.spawn([Health(1)]);
      expect(
        game.pump,
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('observers emit, systems read'),
          ),
        ),
      );
    });

    test('world.emit inside an observer works', () {
      final game = TestGame.headless(
        features: [
          (g) => g
            ..registerComponent<Health>()
            ..observe<Health>(
              onAdd: (world, entity, health) => world.emit(const Ping()),
            ),
        ],
      );
      game.start();
      game.world.registerEvent<Ping>();
      final reader = game.world.eventChannel<Ping>().reader();
      game.world.spawn([Health(1)]);
      game.pump();
      expect(reader.drain().length, 1);
    });

    test('a re-add/re-remove cycle trips the debug cascade guard (S6)', () {
      final world = World();
      ObserverRegistry.of(world).observe<Health>(
        onAdd: (w, entity, health) => w.remove<Health>(entity),
        onRemove: (w, entity, health) => w.add(entity, Health(health.amount)),
      );

      world.spawn([Health(1)]);
      expect(
        SpawnQueue.of(world).flush,
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('Health'),
          ),
        ),
      );
    });

    test('pack-scale volume never trips the cascade guard (S6): one flush '
        'may add an observed component to any number of entities', () {
      final world = World();
      var fires = 0;
      ObserverRegistry.of(world).observe<Health>(
        onAdd: (w, entity, health) => fires++,
      );
      // A fire cone catching a whole pack: 40 fresh adds of one observed
      // type in a single boundary — per-entity counting must let it pass.
      for (var i = 0; i < 40; i++) {
        world.spawn([Health(1)]);
      }
      SpawnQueue.of(world).flush();
      expect(fires, 40);
    });

    test('tag observers receive the canonical witness instance', () {
      const instance = Burning();
      Object? added;
      Object? removed;
      final game = TestGame.headless(
        features: [
          (g) => g.observe<Burning>(
            onAdd: (world, entity, burning) => added = burning,
            onRemove: (world, entity, burning) => removed = burning,
          ),
        ],
      );
      game.start();
      final entity = game.world.spawn([instance]);
      game.pump();
      expect(identical(added, instance), isTrue);

      game.world.remove<Burning>(entity);
      game.pump();
      expect(identical(removed, instance), isTrue);
    });

    test('identical sequence under TestGame.pumpFixed (determinism)', () {
      List<String> run() {
        final log = <String>[];
        final game = TestGame.headless(
          features: [
            (g) => g
              ..registerComponent<Health>()
              ..observe<Health>(
                onAdd: (world, entity, health) =>
                    log.add('add:${entity.index}:${health.amount}'),
                onRemove: (world, entity, health) =>
                    log.add('remove:${entity.index}:${health.amount}'),
              )
              ..addSystem(Schedules.fixedUpdate, (world) {
                world.query<Health>().each((entity, health) {
                  if (health.amount <= 1) world.despawn(entity);
                });
              }, writes: {Health}),
          ],
        );
        game.start();
        game.world.spawn([Health(1)]);
        game.world.spawn([Health(9)]);
        game.pumpFixed(steps: 3);
        return log;
      }

      expect(run(), run());
    });
  });
}
