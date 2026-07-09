// Record-query sugar vs the arity machinery it wraps.
//
// Run: dart run benchmarks/record_query_benchmark.dart [entityCount]
//
// The surface spelling `world.query2<A, B>().each(...)` constructs a small
// view per call (a typed site: it registers stores, claims parked spawn
// parts, and notes types for the access-drift check) and then delegates to
// the same cached `Query2` iteration the classic API uses. This benchmark
// prices exactly that sugar, plus the `.records` for-in form's per-row
// allocation, so the numbers in the design discussion stay honest:
//
//   * classic `Query2.each` — construct once, iterate forever (baseline);
//   * record view, constructed per call — the README idiom inside a system;
//   * record view `.records` for-in — the documented cold-path alternative.
import 'package:scene_dash_v2_core/advanced.dart';
import 'package:scene_dash_v2_core/scene_dash_v2_core.dart'
    show WorldRecordQueries;
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

void main(List<String> args) {
  final n = entityCount(args);
  const dt = 1 / 60;

  final world = World()
    ..stores.register<Position>(ObjectComponentStore<Position>())
    ..stores.register<Velocity>(ObjectComponentStore<Velocity>())
    ..stores.register<Frozen>(TagStore());
  // The record views' typed site consults the spawn queue for parked parts;
  // make sure the resource exists so per-call cost is the realistic one.
  SpawnQueue.of(world);
  for (var i = 0; i < n; i++) {
    final e = world.entities.spawn();
    world
      ..insertNow<Position>(e, Position(i.toDouble(), 0, 0))
      ..insertNow<Velocity>(e, const Velocity(1, 2, 3));
    if (i.isEven) world.insertNow<Frozen>(e, const Frozen());
  }

  // Extension overrides apply at a use site, so the classic (cached)
  // queries are built here and the record views are constructed inline —
  // which is the point: per-call construction is what the record spelling
  // costs.
  final cachedQ2 = ClassicWorldQueries(world).query2<Position, Velocity>();
  final cachedQ2Unfrozen = ClassicWorldQueries(world)
      .query2<Position, Velocity>(withoutTypes: const [Frozen]);

  var sink = 0.0;

  section('Integrate motion: position += velocity * dt', entities: n);
  benchRepeat('classic Query2.each (cached)', n, () {
    cachedQ2.each((e, p, v) {
      p
        ..x += v.x * dt
        ..y += v.y * dt
        ..z += v.z * dt;
    });
  });
  benchRepeat('record view .each (per-call construct)', n, () {
    WorldRecordQueries(world).query2<Position, Velocity>().each((e, p, v) {
      p
        ..x += v.x * dt
        ..y += v.y * dt
        ..z += v.z * dt;
    });
  });
  benchRepeat('record view .records for-in', n, () {
    for (final (_, p, v) in WorldRecordQueries(world).query2<Position, Velocity>().records) {
      p
        ..x += v.x * dt
        ..y += v.y * dt
        ..z += v.z * dt;
    }
  });

  section('Filtered: skip half the entities (Frozen tag)', entities: n);
  benchRepeat('classic Query2.each excludes (cached)', n, () {
    cachedQ2Unfrozen.each((e, p, v) => p.x += v.x * dt);
  });
  benchRepeat('record view .each exclude:', n, () {
    WorldRecordQueries(world)
        .query2<Position, Velocity>(exclude: const [Frozen])
        .each((e, p, v) => p.x += v.x * dt);
  });

  section('Construction alone (object kept observable)', entities: 1);
  benchRepeat('classic query2(...) construct', 1, () {
    sink += identityHashCode(
          ClassicWorldQueries(world).query2<Position, Velocity>(),
        ) &
        1;
  }, minTime: const Duration(milliseconds: 200));
  benchRepeat('record query2(...) construct', 1, () {
    sink += identityHashCode(
          WorldRecordQueries(world).query2<Position, Velocity>(),
        ) &
        1;
  }, minTime: const Duration(milliseconds: 200));

  // Keep `sink` observable so the read loops are not optimized away.
  if (sink.isNaN) print(sink);
}
