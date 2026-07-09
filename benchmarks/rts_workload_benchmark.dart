// Headless RTS-shaped workload: logic, selection filters, spatial grid rebuild,
// nearby queries, and modest spawn/despawn churn.
//
// Run: dart run rts_workload_benchmark.dart [unitCount]
import 'dart:math' as math;

import 'package:scene_dash_v2_core/advanced.dart';
import 'package:scene_dash_v2_benchmarks/harness.dart';

final class Position {
  double x;
  double z;
  Position(this.x, this.z);
}

final class Velocity {
  double x;
  double z;
  Velocity(this.x, this.z);
}

final class Faction {
  int id;
  Faction(this.id);
}

final class Health {
  int value;
  Health(this.value);
}

final class Target {
  int entityIndex;
  Target(this.entityIndex);
}

final class UnitState {
  int mode;
  UnitState(this.mode);
}

final class Selected {
  const Selected();
}

final class UnitBundle implements SceneDashBundle {
  const UnitBundle(this.index);
  final int index;

  @override
  void insertInto(World world, Entity entity) {
    world
      ..insertNow<Position>(
        entity,
        Position((index % 256).toDouble(), (index ~/ 256).toDouble()),
      )
      ..insertNow<Velocity>(entity, Velocity(0.5, 0.25))
      ..insertNow<Faction>(entity, Faction(index & 3))
      ..insertNow<Health>(entity, Health(100))
      ..insertNow<Target>(entity, Target(Entity.invalid.index))
      ..insertNow<UnitState>(entity, UnitState(index & 1));
    if ((index & 15) == 0) {
      world.insertNow<Selected>(entity, const Selected());
    }
  }
}

final class SpatialGrid {
  SpatialGrid(this.cellSize);

  final double cellSize;
  final Map<int, List<int>> cells = <int, List<int>>{};

  void rebuild(ObjectComponentStore<Position> positions) {
    cells.clear();
    for (var dense = 0; dense < positions.length; dense++) {
      final position = positions.valueAt(dense);
      final key = _key(position.x, position.z);
      (cells[key] ??= <int>[]).add(positions.entityIndexAt(dense));
    }
  }

  int nearbyCount(double x, double z) {
    final cx = (x / cellSize).floor();
    final cz = (z / cellSize).floor();
    var count = 0;
    for (var dz = -1; dz <= 1; dz++) {
      for (var dx = -1; dx <= 1; dx++) {
        count += cells[_pack(cx + dx, cz + dz)]?.length ?? 0;
      }
    }
    return count;
  }

  int _key(double x, double z) =>
      _pack((x / cellSize).floor(), (z / cellSize).floor());

  static int _pack(int x, int z) => (x & 0xFFFF) | ((z & 0xFFFF) << 16);
}

World _freshWorld(int count) {
  final world = World()
    ..ensureObjectStore<Position>()
    ..ensureObjectStore<Velocity>()
    ..ensureObjectStore<Faction>()
    ..ensureObjectStore<Health>()
    ..ensureObjectStore<Target>()
    ..ensureObjectStore<UnitState>()
    ..ensureTagStore<Selected>();
  for (var i = 0; i < count; i++) {
    final entity = world.entities.spawn();
    UnitBundle(i).insertInto(world, entity);
  }
  return world;
}

void main(List<String> args) {
  final n = entityCount(args);
  const dt = 1 / 60;
  final world = _freshWorld(n);
  final movement = world.query2<Position, Velocity>();
  final state = world.query3<Health, Target, UnitState>();
  final selected = world.query1<Position>(withTypes: const <Type>[Selected]);
  final positions = world.stores.object<Position>();
  final grid = SpatialGrid(8);
  var sink = 0.0;

  section('RTS logic: movement', entities: n);
  benchRepeat('move 10k-ish units', n, () {
    movement.each((entity, position, velocity) {
      position
        ..x += velocity.x * dt
        ..z += velocity.z * dt;
    });
  });

  section('RTS logic: state/target/economy tick', entities: n);
  benchRepeat('health state target validation', n, () {
    state.each((entity, health, target, unitState) {
      if (health.value <= 0) {
        unitState.mode = 0;
        target.entityIndex = Entity.invalid.index;
      } else if ((entity.index & 31) == 0) {
        unitState.mode = 2;
      }
    });
  });

  section('RTS selection/tag filtering', entities: n);
  benchRepeat('selected unit scan', math.max(1, n ~/ 16), () {
    var local = 0.0;
    selected.each((entity, position) {
      local += position.x;
    });
    sink += local;
  });

  section('RTS spatial grid', entities: n);
  benchRepeat('rebuild uniform grid', n, () {
    grid.rebuild(positions);
  });
  grid.rebuild(positions);
  benchRepeat('nearby candidate lookup', 1024, () {
    var local = 0;
    for (var i = 0; i < 1024; i++) {
      local += grid.nearbyCount((i % 256).toDouble(), (i ~/ 4).toDouble());
    }
    sink += local;
  });

  section('RTS churn: 100 despawns + 100 spawns', entities: 200);
  benchSetup<(World, List<Entity>)>(
    '100/s-style churn batch',
    200,
    setup: () {
      final churnWorld = _freshWorld(n);
      final entities = <Entity>[];
      final store = churnWorld.stores.object<Position>();
      for (var dense = 0; dense < 100; dense++) {
        entities.add(churnWorld.entities.resolve(store.entityIndexAt(dense)));
      }
      return (churnWorld, entities);
    },
    run: (state) {
      final (churnWorld, entities) = state;
      for (final entity in entities) {
        churnWorld.commands.despawn(entity);
      }
      for (var i = 0; i < 100; i++) {
        churnWorld.commands.spawn(UnitBundle(n + i));
      }
      churnWorld.commands.apply();
    },
  );

  if (sink.isNaN) print(sink);
}
