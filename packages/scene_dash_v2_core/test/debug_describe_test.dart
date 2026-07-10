import 'package:scene_dash_v2_core/advanced.dart';
import 'package:test/test.dart';

final class Position {
  double x;
  Position(this.x);
}

final class Health {
  int value;
  Health(this.value);
}

final class Enemy {
  const Enemy();
}

World _worldWithStores() {
  return World()
    ..stores.register<Position>(ObjectComponentStore<Position>())
    ..stores.register<Health>(ObjectComponentStore<Health>())
    ..stores.register<Enemy>(TagStore())
    ..stores.register<Name>(ObjectComponentStore<Name>());
}

void main() {
  group('debugComponentsOf', () {
    test('lists every carried type in store-registration order', () {
      final world = _worldWithStores();
      final e = world.entities.spawn();
      world.insertNow<Health>(e, Health(10));
      world.insertNow<Position>(e, Position(1));
      world.insertNow<Enemy>(e, const Enemy());

      expect(
        world.debugComponentsOf(e),
        <Type>[Position, Health, Enemy],
        reason: 'registration order, not insertion order',
      );
    });

    test('is empty for entities with no components and for stale handles', () {
      final world = _worldWithStores();
      final bare = world.entities.spawn();
      expect(world.debugComponentsOf(bare), isEmpty);

      final dead = world.entities.spawn();
      world.insertNow<Position>(dead, Position(1));
      world.despawnNow(dead);
      expect(world.debugComponentsOf(dead), isEmpty);
    });
  });

  group('debugDescribe', () {
    test('renders entity, name and component list on one line', () {
      final world = _worldWithStores();
      final e = world.entities.spawn();
      world.insertNow<Position>(e, Position(1));
      world.insertNow<Name>(e, const Name('Boss'));

      expect(
        world.debugDescribe(e),
        'Entity(${e.index} v${e.generation}) "Boss" [Position, Name]',
      );
    });

    test('omits the quoted label when the entity has no Name', () {
      final world = _worldWithStores();
      final e = world.entities.spawn();
      world.insertNow<Health>(e, Health(3));

      expect(
        world.debugDescribe(e),
        'Entity(${e.index} v${e.generation}) [Health]',
      );
    });

    test('renders <stale> for dead handles', () {
      final world = _worldWithStores();
      final e = world.entities.spawn();
      world.despawnNow(e);

      expect(
        world.debugDescribe(e),
        'Entity(${e.index} v${e.generation}) <stale>',
      );
    });

    test('a component overriding toString renders its description; '
        'non-overriding components stay types-only', () {
      final world = _worldWithStores()
        ..stores.register<Described>(ObjectComponentStore<Described>());
      final e = world.entities.spawn();
      world.insertNow<Position>(e, Position(1));
      world.insertNow<Described>(e, Described(Machine<Mood>(Mood.calm)));

      expect(
        world.debugDescribe(e),
        'Entity(${e.index} v${e.generation}) [Position, calm (0.00s)]',
        reason: 'Position keeps the type fallback; Described speaks',
      );
    });
  });
}

enum Mood { calm, furious }

/// A component that describes itself — the [Machine] carrier shape.
final class Described {
  final Machine<Mood> mood;
  Described(this.mood);

  @override
  String toString() => '$mood';
}
