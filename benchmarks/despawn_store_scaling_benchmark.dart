// Despawn scaling with registered component-store count.
//
// Run: dart run benchmarks/despawn_store_scaling_benchmark.dart [entityCount]
import 'package:scene_dash_v2_core/advanced.dart';
import 'package:scene_dash_v2_benchmarks/harness.dart';

const _storeCounts = <int>[8, 32, 64, 128];

final class Position {
  double x;
  Position(this.x);
}

final class Velocity {
  double x;
  Velocity(this.x);
}

final class Health {
  int value;
  Health(this.value);
}

final class Faction {
  int value;
  Faction(this.value);
}

final class DummyComponent<T> {
  int value;
  DummyComponent(this.value);
}

final class _D0 {}

final class _D1 {}

final class _D2 {}

final class _D3 {}

final class _D4 {}

final class _D5 {}

final class _D6 {}

final class _D7 {}

final class _D8 {}

final class _D9 {}

final class _D10 {}

final class _D11 {}

final class _D12 {}

final class _D13 {}

final class _D14 {}

final class _D15 {}

final class _D16 {}

final class _D17 {}

final class _D18 {}

final class _D19 {}

final class _D20 {}

final class _D21 {}

final class _D22 {}

final class _D23 {}

final class _D24 {}

final class _D25 {}

final class _D26 {}

final class _D27 {}

final class _D28 {}

final class _D29 {}

final class _D30 {}

final class _D31 {}

final class _D32 {}

final class _D33 {}

final class _D34 {}

final class _D35 {}

final class _D36 {}

final class _D37 {}

final class _D38 {}

final class _D39 {}

final class _D40 {}

final class _D41 {}

final class _D42 {}

final class _D43 {}

final class _D44 {}

final class _D45 {}

final class _D46 {}

final class _D47 {}

final class _D48 {}

final class _D49 {}

final class _D50 {}

final class _D51 {}

final class _D52 {}

final class _D53 {}

final class _D54 {}

final class _D55 {}

final class _D56 {}

final class _D57 {}

final class _D58 {}

final class _D59 {}

final class _D60 {}

final class _D61 {}

final class _D62 {}

final class _D63 {}

final class _D64 {}

final class _D65 {}

final class _D66 {}

final class _D67 {}

final class _D68 {}

final class _D69 {}

final class _D70 {}

final class _D71 {}

final class _D72 {}

final class _D73 {}

final class _D74 {}

final class _D75 {}

final class _D76 {}

final class _D77 {}

final class _D78 {}

final class _D79 {}

final class _D80 {}

final class _D81 {}

final class _D82 {}

final class _D83 {}

final class _D84 {}

final class _D85 {}

final class _D86 {}

final class _D87 {}

final class _D88 {}

final class _D89 {}

final class _D90 {}

final class _D91 {}

final class _D92 {}

final class _D93 {}

final class _D94 {}

final class _D95 {}

final class _D96 {}

final class _D97 {}

final class _D98 {}

final class _D99 {}

final class _D100 {}

final class _D101 {}

final class _D102 {}

final class _D103 {}

final class _D104 {}

final class _D105 {}

final class _D106 {}

final class _D107 {}

final class _D108 {}

final class _D109 {}

final class _D110 {}

final class _D111 {}

final class _D112 {}

final class _D113 {}

final class _D114 {}

final class _D115 {}

final class _D116 {}

final class _D117 {}

final class _D118 {}

final class _D119 {}

final class _D120 {}

final class _D121 {}

final class _D122 {}

final class _D123 {}

World _worldWithStoreCount(int storeCount) {
  final world = World()
    ..ensureObjectStore<Position>()
    ..ensureObjectStore<Velocity>()
    ..ensureObjectStore<Health>()
    ..ensureObjectStore<Faction>();
  for (var i = 0; i < storeCount - 4; i++) {
    _dummyRegistrations[i](world);
  }
  return world;
}

typedef _RegisterDummy = void Function(World world);

final List<_RegisterDummy> _dummyRegistrations = <_RegisterDummy>[
  (world) => world.ensureObjectStore<DummyComponent<_D0>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D1>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D2>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D3>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D4>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D5>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D6>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D7>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D8>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D9>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D10>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D11>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D12>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D13>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D14>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D15>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D16>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D17>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D18>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D19>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D20>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D21>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D22>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D23>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D24>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D25>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D26>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D27>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D28>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D29>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D30>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D31>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D32>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D33>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D34>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D35>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D36>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D37>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D38>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D39>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D40>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D41>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D42>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D43>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D44>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D45>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D46>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D47>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D48>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D49>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D50>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D51>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D52>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D53>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D54>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D55>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D56>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D57>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D58>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D59>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D60>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D61>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D62>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D63>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D64>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D65>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D66>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D67>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D68>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D69>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D70>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D71>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D72>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D73>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D74>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D75>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D76>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D77>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D78>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D79>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D80>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D81>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D82>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D83>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D84>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D85>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D86>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D87>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D88>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D89>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D90>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D91>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D92>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D93>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D94>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D95>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D96>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D97>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D98>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D99>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D100>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D101>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D102>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D103>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D104>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D105>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D106>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D107>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D108>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D109>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D110>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D111>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D112>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D113>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D114>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D115>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D116>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D117>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D118>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D119>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D120>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D121>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D122>>(),
  (world) => world.ensureObjectStore<DummyComponent<_D123>>(),
];

void main(List<String> args) {
  final n = entityCount(args);
  for (final storeCount in _storeCounts) {
    section('Mass despawn with $storeCount registered stores', entities: n);
    benchSetup<(World, List<Entity>)>(
      'despawn fixed 4-component entities',
      n,
      setup: () {
        final world = _worldWithStoreCount(storeCount);
        final entities = <Entity>[];
        for (var i = 0; i < n; i++) {
          final entity = world.entities.spawn();
          world
            ..insertNow<Position>(entity, Position(0))
            ..insertNow<Velocity>(entity, Velocity(1))
            ..insertNow<Health>(entity, Health(100))
            ..insertNow<Faction>(entity, Faction(i & 3));
          entities.add(entity);
        }
        return (world, entities);
      },
      run: (state) {
        final (world, entities) = state;
        for (final entity in entities) {
          world.despawnNow(entity);
        }
      },
    );
  }
}
