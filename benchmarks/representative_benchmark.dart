// A representative steady-state object-ECS frame: many entities, several
// component stores, and filtered queries — the workload the docs ask for
// (10,000 gameplay entities, multiple filters). The scene-sync half needs
// flutter_scene and belongs in an on-device benchmark; this measures the
// pure-ECS query cost that runs every frame.
//
// Run: dart run benchmarks/representative_benchmark.dart [entityCount]
import 'package:scene_dash_v2_core/advanced.dart';
import 'package:scene_dash_v2_benchmarks/harness.dart';

final class Position {
  double x;
  double y;
  double z;
  Position(this.x, this.y, this.z);
}

final class Velocity {
  final double x;
  final double y;
  final double z;
  const Velocity(this.x, this.y, this.z);
}

final class Health {
  double current;
  Health(this.current);
}

final class Player {
  const Player();
}

final class Frozen {
  const Frozen();
}

World _build(int n) {
  final world = World()
    ..stores.register<Position>(ObjectComponentStore<Position>())
    ..stores.register<Velocity>(ObjectComponentStore<Velocity>())
    ..stores.register<Health>(ObjectComponentStore<Health>())
    ..stores.register<Player>(TagStore())
    ..stores.register<Frozen>(TagStore());
  for (var i = 0; i < n; i++) {
    final e = world.entities.spawn();
    world
      ..insertNow<Position>(e, Position(i.toDouble(), 0, 0))
      ..insertNow<Velocity>(e, const Velocity(1, 2, 3));
    if (i % 2 == 0) world.insertNow<Player>(e, const Player());
    if (i % 4 == 0) world.insertNow<Frozen>(e, const Frozen());
    if (i % 3 == 0) world.insertNow<Health>(e, Health(100));
  }
  return world;
}

void main(List<String> args) {
  final n = entityCount(args);
  const dt = 1 / 60;
  final world = _build(n);

  // Movement over non-frozen entities (~75% of N pass the filter).
  final movers = world.query2<Position, Velocity>(withoutTypes: const [Frozen]);
  // A filtered single-component scan over players (~50% of N).
  final players = world.query1<Position>(withTypes: const [Player]);
  // A three-component query (entities that also have Health, ~one third).
  final living = world.query3<Position, Velocity, Health>();

  var sink = 0.0;

  section('Representative per-frame object-ECS queries', entities: n);

  benchRepeat('move: Query2<Position,Velocity> excl. Frozen', n, () {
    movers.each((entity, p, v) {
      p
        ..x += v.x * dt
        ..y += v.y * dt
        ..z += v.z * dt;
    });
  });

  benchRepeat('scan: Query1<Position> req. Player', n, () {
    var s = 0.0;
    players.each((entity, p) => s += p.x);
    sink += s;
  });

  benchRepeat('regen: Query3<Position,Velocity,Health>', n, () {
    living.each((entity, p, v, h) {
      if (h.current < 100) h.current += 1;
    });
  });

  if (sink.isNaN) print(sink);
}
