// Structural-change costs: spawning, despawning, component insert/remove and
// deferred command application.
//
// Run: dart run benchmarks/spawn_despawn_benchmark.dart [entityCount]
import 'package:scene_dash_v2_core/advanced.dart';
import 'package:scene_dash_v2_benchmarks/harness.dart';

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

World _freshWorld() => World()
  ..stores.register<Position>(ObjectComponentStore<Position>())
  ..stores.register<Velocity>(ObjectComponentStore<Velocity>());

void main(List<String> args) {
  final n = entityCount(args);

  section('Spawn entity + insert two components', entities: n);
  benchSetup<World>(
    'spawn N',
    n,
    setup: _freshWorld,
    run: (w) {
      for (var i = 0; i < n; i++) {
        final e = w.entities.spawn();
        w
          ..insertNow<Position>(e, Position(0, 0))
          ..insertNow<Velocity>(e, Velocity(1, 1));
      }
    },
  );

  section('Despawn entity (strips all components)', entities: n);
  benchSetup<(World, List<Entity>)>(
    'despawn N',
    n,
    setup: () {
      final w = _freshWorld();
      final es = <Entity>[];
      for (var i = 0; i < n; i++) {
        final e = w.entities.spawn();
        w
          ..insertNow<Position>(e, Position(0, 0))
          ..insertNow<Velocity>(e, Velocity(1, 1));
        es.add(e);
      }
      return (w, es);
    },
    run: (s) {
      final (w, es) = s;
      for (final e in es) {
        w.despawnNow(e);
      }
    },
  );

  section('Component insert', entities: n);
  benchSetup<(World, List<Entity>)>(
    'insert Position on N',
    n,
    setup: () {
      final w = _freshWorld();
      final es = <Entity>[for (var i = 0; i < n; i++) w.entities.spawn()];
      return (w, es);
    },
    run: (s) {
      final (w, es) = s;
      for (final e in es) {
        w.insertNow<Position>(e, Position(0, 0));
      }
    },
  );

  section('Component remove (swap removal)', entities: n);
  benchSetup<(World, List<Entity>)>(
    'remove Position from N',
    n,
    setup: () {
      final w = _freshWorld();
      final es = <Entity>[];
      for (var i = 0; i < n; i++) {
        final e = w.entities.spawn();
        w.insertNow<Position>(e, Position(0, 0));
        es.add(e);
      }
      return (w, es);
    },
    run: (s) {
      final (w, es) = s;
      for (final e in es) {
        w.removeNow<Position>(e);
      }
    },
  );

  section('Command buffer: apply N deferred inserts', entities: n);
  benchSetup<World>(
    'apply N queued inserts',
    n,
    setup: () {
      final w = _freshWorld();
      for (var i = 0; i < n; i++) {
        final e = w.commands.spawn().entity;
        w.commands.insert<Position>(e, Position(0, 0));
      }
      return w;
    },
    run: (w) => w.commands.apply(),
  );
}
