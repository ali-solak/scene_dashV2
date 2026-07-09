// Full-cycle structural churn costs: command recording, command application,
// and record+apply across repeated frames.
//
// Run: dart run benchmarks/structural_churn_benchmark.dart
import 'package:scene_dash_v2_core/advanced.dart';
import 'package:scene_dash_v2_benchmarks/harness.dart';

const _frames = 180;
const _spawnCounts = <int>[100, 1000];

final class C1 {
  int value;
  C1(this.value);
}

final class C2 {
  int value;
  C2(this.value);
}

final class C3 {
  int value;
  C3(this.value);
}

final class C4 {
  int value;
  C4(this.value);
}

final class C5 {
  int value;
  C5(this.value);
}

final class C6 {
  int value;
  C6(this.value);
}

final class Bundle2 implements SceneDashBundle {
  const Bundle2(this.value);
  final int value;

  @override
  void insertInto(World world, Entity entity) {
    world
      ..insertNow<C1>(entity, C1(value))
      ..insertNow<C2>(entity, C2(value));
  }
}

final class Bundle6 implements SceneDashBundle {
  const Bundle6(this.value);
  final int value;

  @override
  void insertInto(World world, Entity entity) {
    world
      ..insertNow<C1>(entity, C1(value))
      ..insertNow<C2>(entity, C2(value))
      ..insertNow<C3>(entity, C3(value))
      ..insertNow<C4>(entity, C4(value))
      ..insertNow<C5>(entity, C5(value))
      ..insertNow<C6>(entity, C6(value));
  }
}

World _freshWorld() => World()
  ..ensureObjectStore<C1>()
  ..ensureObjectStore<C2>()
  ..ensureObjectStore<C3>()
  ..ensureObjectStore<C4>()
  ..ensureObjectStore<C5>()
  ..ensureObjectStore<C6>();

void _recordSpawns(
  World world,
  int count,
  SceneDashBundle Function(int value) bundle,
) {
  for (var i = 0; i < count; i++) {
    world.commands.spawn(bundle(i));
  }
}

void _recordMixed(World world, List<Entity> entities, int count) {
  for (var i = 0; i < count; i++) {
    final entity = entities[i % entities.length];
    world.commands
      ..insert<C1>(entity, C1(i))
      ..remove<C2>(entity)
      ..insert<C2>(entity, C2(i))
      ..despawn(entity);
    entities[i % entities.length] =
        world.commands.spawn(const Bundle2(0)).entity;
  }
}

void main() {
  for (final count in _spawnCounts) {
    final ops = count * _frames;

    section('Command record only: Bundle2', entities: ops);
    benchSetup<World>(
      'record spawn Bundle2',
      ops,
      setup: _freshWorld,
      run: (world) {
        for (var frame = 0; frame < _frames; frame++) {
          _recordSpawns(world, count, Bundle2.new);
        }
      },
    );

    section('Command apply only: Bundle2', entities: ops);
    benchSetup<World>(
      'apply queued Bundle2 spawns',
      ops,
      setup: () {
        final world = _freshWorld();
        for (var frame = 0; frame < _frames; frame++) {
          _recordSpawns(world, count, Bundle2.new);
        }
        return world;
      },
      run: (world) => world.commands.apply(),
    );

    section('Command record + apply per frame: Bundle2', entities: ops);
    benchSetup<World>(
      'record+apply Bundle2 spawns',
      ops,
      setup: _freshWorld,
      run: (world) {
        for (var frame = 0; frame < _frames; frame++) {
          _recordSpawns(world, count, Bundle2.new);
          world.commands.apply();
        }
      },
    );

    section('Command record + apply per frame: Bundle6', entities: ops);
    benchSetup<World>(
      'record+apply Bundle6 spawns',
      ops,
      setup: _freshWorld,
      run: (world) {
        for (var frame = 0; frame < _frames; frame++) {
          _recordSpawns(world, count, Bundle6.new);
          world.commands.apply();
        }
      },
    );

    section('Mixed record + apply: replace/remove/despawn/spawn',
        entities: ops);
    benchSetup<(World, List<Entity>)>(
      'mixed churn Bundle2',
      ops,
      setup: () {
        final world = _freshWorld();
        final entities = <Entity>[];
        for (var i = 0; i < count; i++) {
          final entity = world.entities.spawn();
          const Bundle2(0).insertInto(world, entity);
          entities.add(entity);
        }
        return (world, entities);
      },
      run: (state) {
        final (world, entities) = state;
        for (var frame = 0; frame < _frames; frame++) {
          _recordMixed(world, entities, count);
          world.commands.apply();
        }
      },
    );
  }
}
