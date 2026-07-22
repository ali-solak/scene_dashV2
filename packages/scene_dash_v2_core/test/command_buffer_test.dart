import 'package:scene_dash_v2_core/advanced.dart';
import 'package:test/test.dart';

final class Health {
  final int value;
  const Health(this.value);
}

final class _HealthBundle implements SceneDashBundle {
  final Health health;
  const _HealthBundle(this.health);

  @override
  void insertInto(World world, Entity entity) {
    world.insertNow<Health>(entity, health);
  }
}

void main() {
  group('Commands (deferred structural changes)', () {
    late World world;

    setUp(() {
      world = World()..stores.register<Health>(ObjectComponentStore<Health>());
    });

    test('spawn reserves a live entity immediately', () {
      final entity = world.commands.spawn().entity;
      expect(world.entities.isAlive(entity), isTrue);
    });

    test('insert is deferred until apply', () {
      final entity = world.commands.spawn().entity;
      world.commands.insert<Health>(entity, const Health(100));

      expect(
        world.stores.object<Health>().containsIndex(entity.index),
        isFalse,
      );
      world.commands.apply();
      expect(world.stores.object<Health>().valueOf(entity.index)?.value, 100);
    });

    test('remove and despawn are deferred until apply', () {
      final entity = world.commands.spawn().entity;
      world.commands.insert<Health>(entity, const Health(50));
      world.commands.apply();

      world.commands.despawn(entity);
      expect(world.entities.isAlive(entity), isTrue, reason: 'still deferred');
      world.commands.apply();

      expect(world.entities.isAlive(entity), isFalse);
      expect(
        world.stores.object<Health>().containsIndex(entity.index),
        isFalse,
      );
    });

    test('two despawns of the same entity in one flush are idempotent', () {
      final entity = world.commands.spawn().entity;
      world.commands.apply();

      // Two systems independently queue the same despawn (a lifetime expiry
      // racing a hit, for example); the second must be a no-op, not a crash.
      world.commands.despawn(entity);
      world.commands.despawn(entity);
      expect(() => world.commands.apply(), returnsNormally);
      expect(world.entities.isAlive(entity), isFalse);

      // The freed slot's next tenant is untouched by the stale command
      // history: a fresh flush pair despawns only what it targets.
      final reused = world.commands.spawn().entity;
      world.commands.apply();
      expect(reused.index, entity.index);
      expect(world.entities.isAlive(reused), isTrue);
    });

    test('apply clears the queue', () {
      final entity = world.commands.spawn().entity;
      world.commands.insert<Health>(entity, const Health(1));
      expect(world.commands.isEmpty, isFalse);
      world.commands.apply();
      expect(world.commands.isEmpty, isTrue);
    });

    test('entity commands provide fluent deferred operations', () {
      final entity = world.commands.spawn().entity;
      world.commands
          .entity(entity)
          .insert<Health>(const Health(25))
          .remove<Health>()
          .insert<Health>(const Health(75));

      expect(world.tryGet<Health>(entity), isNull);
      world.commands.apply();
      expect(world.get<Health>(entity).value, 75);

      world.commands.entity(entity).despawn();
      expect(world.entities.isAlive(entity), isTrue);
      world.commands.apply();
      expect(world.entities.isAlive(entity), isFalse);
    });

    test('spawn returns entity commands for in-place decoration', () {
      final spawned = world.commands.spawn()..insert<Health>(const Health(10));

      expect(world.tryGet<Health>(spawned.entity), isNull);
      world.commands.apply();
      expect(world.get<Health>(spawned.entity).value, 10);
    });

    test('inserts chained on spawn apply after the bundle, same flush', () {
      final entity = world.commands
          .spawn(_HealthBundle(const Health(1)))
          .insert<Health>(const Health(99))
          .entity;

      world.commands.apply();
      expect(
        world.get<Health>(entity).value,
        99,
        reason: 'the chained insert overrides the bundle component',
      );
    });

    test('stale command targets assert when applied in debug mode', () {
      final entity = world.commands.spawn().entity;
      world.commands.despawn(entity);
      world.commands.apply();

      world.commands.insert<Health>(entity, const Health(1));
      expect(world.commands.apply, throwsA(isA<AssertionError>()));
    });
  });
}
