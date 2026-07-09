// Query-side Entity handle cost probe.
//
// Run: dart run benchmarks/query_entity_allocation_benchmark.dart [entityCount]
import 'package:scene_dash_v2_core/advanced.dart';
import 'package:scene_dash_v2_benchmarks/harness.dart';

final class Position {
  double x;
  Position(this.x);
}

void main(List<String> args) {
  final n = entityCount(args);
  final world = World()..ensureObjectStore<Position>();
  final store = world.stores.object<Position>();
  for (var i = 0; i < n; i++) {
    final entity = world.entities.spawn();
    world.insertNow<Position>(entity, Position(i.toDouble()));
  }
  final query = world.query1<Position>();
  var sink = 0;

  section('Query entity handle probe', entities: n);
  benchRepeat('Query1.each entity ignored', n, () {
    query.each((entity, position) {
      position.x += 1;
    });
  });
  benchRepeat('Query1.each entity consumed', n, () {
    var local = 0;
    query.each((entity, position) {
      position.x += 1;
      local += entity.index;
    });
    sink += local;
  });
  benchRepeat('store direct value loop (entity-free probe)', n, () {
    for (var dense = 0; dense < store.length; dense++) {
      store.valueAt(dense).x += 1;
    }
  });

  if (sink == -1) print(sink);
}
