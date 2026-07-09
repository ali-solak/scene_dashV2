import 'package:scene_dash_v2_core/advanced.dart';
import 'package:test/test.dart';

final class Position {
  double x;
  Position(this.x);
}

final class Config {
  final int value;
  const Config(this.value);
}

void main() {
  group('World helpers', () {
    late World world;

    setUp(() {
      world = World()
        ..stores.register<Position>(ObjectComponentStore<Position>());
    });

    test('has, get and tryGet reflect component membership', () {
      final entity = world.entities.spawn();
      final missing = world.entities.spawn();
      world.insertNow<Position>(entity, Position(3));

      expect(world.isAlive(entity), isTrue);
      expect(world.has<Position>(entity), isTrue);
      expect(world.get<Position>(entity).x, 3);
      expect(world.tryGet<Position>(entity)?.x, 3);

      expect(world.has<Position>(missing), isFalse);
      expect(world.tryGet<Position>(missing), isNull);
      expect(() => world.get<Position>(missing), throwsStateError);
    });

    test('helpers treat stale entities as absent', () {
      final entity = world.entities.spawn();
      world.insertNow<Position>(entity, Position(5));
      world.despawnNow(entity);

      expect(world.isAlive(entity), isFalse);
      expect(world.has<Position>(entity), isFalse);
      expect(world.tryGet<Position>(entity), isNull);
      expect(() => world.get<Position>(entity), throwsStateError);
    });

    test('tryGet2 returns both components or null', () {
      world.stores.register<Config>(ObjectComponentStore<Config>());
      final entity = world.entities.spawn();
      world.insertNow<Position>(entity, Position(3));
      world.insertNow<Config>(entity, const Config(7));

      final pair = world.tryGet2<Position, Config>(entity);
      expect(pair, isNotNull);
      expect(pair!.$1.x, 3);
      expect(pair.$2.value, 7);

      // Mutating a record field writes through to the live component.
      pair.$1.x = 42;
      expect(world.get<Position>(entity).x, 42);
    });

    test('tryGet2 is null when either component is missing', () {
      world.stores.register<Config>(ObjectComponentStore<Config>());
      final positionOnly = world.entities.spawn();
      world.insertNow<Position>(positionOnly, Position(1));
      expect(world.tryGet2<Position, Config>(positionOnly), isNull);
      expect(world.tryGet2<Config, Position>(positionOnly), isNull);
    });

    test('tryGet2 is null for stale entities and unregistered stores', () {
      final entity = world.entities.spawn();
      world.insertNow<Position>(entity, Position(1));
      // Config's store is not registered in this test.
      expect(world.tryGet2<Position, Config>(entity), isNull);

      world.despawnNow(entity);
      expect(world.tryGet2<Position, Position>(entity), isNull);
    });

    test('tryGet3 requires all three components', () {
      world.stores.register<Config>(ObjectComponentStore<Config>());
      world.stores.register<_Extra>(ObjectComponentStore<_Extra>());
      final entity = world.entities.spawn();
      world.insertNow<Position>(entity, Position(3));
      world.insertNow<Config>(entity, const Config(7));

      expect(world.tryGet3<Position, Config, _Extra>(entity), isNull);

      world.insertNow<_Extra>(entity, const _Extra(11));
      final triple = world.tryGet3<Position, Config, _Extra>(entity);
      expect(triple, isNotNull);
      expect(triple!.$1.x, 3);
      expect(triple.$2.value, 7);
      expect(triple.$3.value, 11);
    });

    test('resource helpers delegate to Resources', () {
      expect(world.hasResource<Config>(), isFalse);
      expect(world.tryResource<Config>(), isNull);

      world.resources.insert<Config>(const Config(9));

      expect(world.hasResource<Config>(), isTrue);
      expect(world.tryResource<Config>()?.value, 9);
      expect(world.resource<Config>().value, 9);
    });

    test('ensure helpers create and reuse stores in registration order', () {
      final ensuredPosition = world.ensureObjectStore<Position>();
      final ensuredConfig = world.ensureObjectStore<Config>();
      final tag = world.ensureTagStore<_WorldTag>();

      expect(world.ensureObjectStore<Position>(), same(ensuredPosition));
      expect(world.ensureObjectStore<Config>(), same(ensuredConfig));
      expect(world.ensureTagStore<_WorldTag>(), same(tag));
      expect(world.stores.all.toList(), <ComponentStore>[
        ensuredPosition,
        ensuredConfig,
        tag,
      ]);
    });
  });
}

final class _WorldTag {
  const _WorldTag();
}

final class _Extra {
  final int value;
  const _Extra(this.value);
}
