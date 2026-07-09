// Flat object iteration vs. object sparse-set queries.
//
// Run: dart run benchmarks/object_query_benchmark.dart [entityCount]
//
// The point of this benchmark is honesty: it puts a straightforward
// `List<Actor>` loop next to the equivalent Scene-Dash query so the *cost* of
// the sparse-set indirection is visible. Do not read these as "the ECS is
// faster"; read them as "the ECS query costs roughly X over a flat loop here".
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

final class Frozen {
  const Frozen();
}

/// The flat-loop baseline: a plain object with both components inline.
class Actor {
  final Position position;
  final Velocity velocity;
  final bool frozen;
  Actor(this.position, this.velocity, this.frozen);
}

void main(List<String> args) {
  final n = entityCount(args);
  const dt = 1 / 60;

  final actors = <Actor>[
    for (var i = 0; i < n; i++)
      Actor(Position(i.toDouble(), 0, 0), const Velocity(1, 2, 3), i.isEven),
  ];

  final world = World()
    ..stores.register<Position>(ObjectComponentStore<Position>())
    ..stores.register<Velocity>(ObjectComponentStore<Velocity>())
    ..stores.register<Frozen>(TagStore());
  for (var i = 0; i < n; i++) {
    final e = world.entities.spawn();
    world
      ..insertNow<Position>(e, Position(i.toDouble(), 0, 0))
      ..insertNow<Velocity>(e, const Velocity(1, 2, 3));
    if (i.isEven) world.insertNow<Frozen>(e, const Frozen());
  }

  final q2 = world.query2<Position, Velocity>();
  final q1 = world.query1<Position>();
  final q2Unfrozen =
      world.query2<Position, Velocity>(withoutTypes: const [Frozen]);

  var sink = 0.0;

  section('Integrate motion: position += velocity * dt', entities: n);
  benchRepeat('flat List<Actor> loop', n, () {
    for (var i = 0; i < actors.length; i++) {
      final a = actors[i];
      a.position
        ..x += a.velocity.x * dt
        ..y += a.velocity.y * dt
        ..z += a.velocity.z * dt;
    }
  });
  benchRepeat('object sparse Query2', n, () {
    q2.each((e, p, v) {
      p
        ..x += v.x * dt
        ..y += v.y * dt
        ..z += v.z * dt;
    });
  });

  section('Single-component read (sum position.x)', entities: n);
  benchRepeat('flat List<Actor> loop', n, () {
    var s = 0.0;
    for (var i = 0; i < actors.length; i++) {
      s += actors[i].position.x;
    }
    sink += s;
  });
  benchRepeat('object sparse Query1', n, () {
    var s = 0.0;
    q1.each((e, p) => s += p.x);
    sink += s;
  });

  section('Filtered: skip half the entities (Frozen tag)', entities: n);
  benchRepeat('flat loop + bool check', n, () {
    for (var i = 0; i < actors.length; i++) {
      final a = actors[i];
      if (a.frozen) continue;
      a.position.x += a.velocity.x * dt;
    }
  });
  benchRepeat('object sparse Query2 excludes Frozen', n, () {
    q2Unfrozen.each((e, p, v) => p.x += v.x * dt);
  });

  // Keep `sink` observable so the read loops are not optimized away.
  if (sink.isNaN) print(sink);
}
