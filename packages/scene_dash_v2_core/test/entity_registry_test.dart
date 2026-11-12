import 'package:scene_dash_v2_core/advanced.dart';
import 'package:test/test.dart';

void main() {
  group('EntityRegistry', () {
    test('spawns distinct entities', () {
      final registry = EntityRegistry();
      final a = registry.spawn();
      final b = registry.spawn();
      expect(a, isNot(equals(b)));
      expect(registry.aliveCount, 2);
    });

    test('reuses freed indices with a bumped generation', () {
      final registry = EntityRegistry();
      final first = registry.spawn();
      expect(registry.despawn(first), isTrue);

      final reused = registry.spawn();
      expect(reused.index, first.index, reason: 'index is reused LIFO');
      expect(reused.generation, isNot(first.generation));
      expect(registry.aliveCount, 1);
    });

    test('rejects a stale handle after the slot is reused', () {
      final registry = EntityRegistry();
      final stale = registry.spawn();
      registry.despawn(stale);
      final fresh = registry.spawn();

      expect(registry.isAlive(stale), isFalse);
      expect(registry.isAlive(fresh), isTrue);
    });

    test('despawning a stale handle is a no-op', () {
      final registry = EntityRegistry();
      final entity = registry.spawn();
      expect(registry.despawn(entity), isTrue);
      expect(registry.despawn(entity), isFalse);
    });

    test('grows capacity beyond the initial allocation', () {
      final registry = EntityRegistry(initialCapacity: 2);
      final entities = <Entity>[for (var i = 0; i < 100; i++) registry.spawn()];
      expect(registry.aliveCount, 100);
      for (final entity in entities) {
        expect(registry.isAlive(entity), isTrue);
      }
    });
  });

  test('Entity packs index and generation within 53 bits', () {
    const top = Entity(Entity.maxIndex, Entity.generationMask);
    expect(top.index, Entity.maxIndex);
    expect(top.generation, Entity.generationMask);
    expect((top as int) <= 9007199254740991, isTrue);
    expect(const Entity(5, 3), const Entity(5, 3));
    expect(const Entity(5, 3) == const Entity(5, 4), isFalse);
    expect(const Entity(5, Entity.generationMask + 1).generation, 0);
    expect(Entity.invalid.isValid, isFalse);
    expect(const Entity(5, 3).label, 'Entity(5 v3)');
  });

  test('a slot reused a million times still tells handles apart', () {
    final registry = EntityRegistry();
    final first = registry.spawn();
    var entity = first;
    for (var i = 0; i < 1 << 21; i++) {
      registry.despawn(entity);
      entity = registry.spawn();
    }
    expect(entity.index, first.index);
    expect(entity.generation, 1 << 21);
    expect(registry.isAlive(first), isFalse);
  });
}
