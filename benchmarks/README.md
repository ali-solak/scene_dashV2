# Scene-Dash v2 benchmarks

These benchmarks measure the real cost of the object-first sparse-set
architecture — and of the v2 record-query sugar over the arity machinery
it wraps. They are regression and sanity tools, not marketing material:
queries buy organization and component selection at a measurable
per-entity cost, and the surface spelling buys ergonomics at a measurable
per-call cost. Both costs should stay small and *known*.

## Running

JIT runs are useful while iterating:

```bash
dart run benchmarks/object_query_benchmark.dart [entityCount]
dart run benchmarks/record_query_benchmark.dart [entityCount]
dart run benchmarks/spawn_despawn_benchmark.dart [entityCount]
dart run benchmarks/representative_benchmark.dart [entityCount]
dart run benchmarks/transform_sync_benchmark.dart [entityCount]
dart run benchmarks/structural_churn_benchmark.dart
dart run benchmarks/despawn_store_scaling_benchmark.dart [entityCount]
dart run benchmarks/query_entity_allocation_benchmark.dart [entityCount]
dart run benchmarks/rts_workload_benchmark.dart [unitCount]
dart run benchmarks/schedule_dispatch_benchmark.dart [systemCount]
```

Use `dart compile exe` AOT executables for numbers that should be
compared over time; treat desktop JIT/AOT numbers as CPU-shape signals and
validate render-facing claims on a device. Captured runs live under
[`results/`](results/).

## The record-query sugar, priced

`record_query_benchmark.dart` is the v2-specific suite: the surface
spelling `world.query2<A, B>().each(...)` constructs a small view per call
(a typed site — it registers stores, claims parked spawn parts, and notes
types for the access-drift check) and then delegates to the same cached
arity iteration the classic API uses. Desktop JIT, N = 10k
(`results/2026-07-09-jit-desktop.txt`):

| Measurement | JIT result |
| --- | ---: |
| classic `Query2.each` (construct once, cached) | 9.7 ns/entity |
| record view `.each`, constructed per call | 9.7 ns/entity |
| record view `.records` for-in | 21.0 ns/entity |
| classic `query2(...)` construction alone | ~87 ns/call |
| record `query2(...)` construction alone | ~75 ns/call |

Reading it: **the sugar is free where it matters.** Per-entity iteration
through the record view is indistinguishable from the cached classic
query, because `.each` *is* the classic loop behind a façade. The per-call
construction is well under 100 ns — noise unless a system constructs
queries in an inner loop — and the `.records` for-in form costs about one
extra allocation-driven 2× per row, which is exactly why the docs lead
with `.each` and call records the cold-path alternative.

## The carried suites

The remaining benchmarks are the v1 core suite, carried onto the v2
machinery tier (`package:scene_dash_v2_core/advanced.dart`) unchanged in
what they measure:

- `object_query` — flat `List<Actor>` loops vs sparse `Query1`/`Query2`,
  with and without a tag filter. The honesty baseline: the sparse-set
  indirection costs a few ns/entity over a flat loop.
- `representative` — a game-shaped frame: movement, a player scan, a
  regen pass.
- `spawn_despawn` — bundle recording + apply cost per entity.
- `structural_churn` — add/remove component thrash.
- `despawn_store_scaling` — despawn cost as the store count grows.
- `query_entity_allocation` — the entity parameter's cost when ignored
  vs consumed.
- `rts_workload` — movement/state/selection passes plus a spatial-grid
  rebuild and nearby lookups at RTS scale.
- `transform_sync` — full-TRS vs changed-only transform sync.
- `schedule_dispatch` — the fixed frame skeleton: per-system dispatch,
  `runIf` gating, many distinct query executions, event channel
  maintenance.

The v1 AOT capture (2026-06-23, Dart 3.13 dev) remains the reference
shape: sparse queries ~7 ns/entity vs ~1 ns flat, dispatch ~1.6 ns/system,
a query execution ~15–60 ns fixed plus the per-entity rate — so even
thousands of query executions per frame are dominated by per-entity work,
not the skeleton. Re-capture on this machine before relying on absolute
numbers.

## On-device scene benchmark

[`examples/scene_benchmark`](../examples/scene_benchmark) renders a 40×40
grid of **1,600 cubes** on a device in Flutter profile mode (Flutter GPU /
Impeller). All modes use the same grid, cube geometry, material, camera,
light, viewport, and no animation:

| Mode | Purpose |
| --- | --- |
| `static` | Direct `flutter_scene` `Node` per cube, no ECS. |
| `mountOnly` | ECS lifecycle plus `SceneNode` mounting, no `SceneTransform` sync (hand-assembled from the machinery tier). |
| `ecs` | The shipped path — `SceneGame.boot` with an entity per cube, `SceneNode` + `SceneTransform` full sync. |
| `instanced` | One `flutter_scene` `InstancedMesh` containing the same visible cubes. |

The app prints stable machine-readable lines
(`SCENE_BENCHMARK config|result|system ...`). Run one mode:

```powershell
cd examples\scene_benchmark

flutter run --profile -d <device> --enable-flutter-gpu `
  --dart-define=benchmarkMode=ecs `
  --dart-define=profileSystems=false `
  --dart-define=warmupFrames=60 `
  --dart-define=sampleFrames=180
```

Alternate modes across several rounds so thermal drift doesn't bias one
mode, then aggregate the captured output:

```powershell
cd benchmarks
dart run aggregate_scene_benchmark.dart results\<capture>.txt
```

Set `profileSystems=true` in a separate run for per-system timing lines;
profiler data is reset after warmup so run counts match the sampled frame
window. The v1 Pixel 8 capture (2026-06-23) is the reference shape: the
ECS entity-per-cube path costs a few ms of build time over raw static
nodes at 1,600 visible cubes, and instancing beats everything by an order
of magnitude — the reason the gizmo layer and `decor/` use instanced
pools. Re-capture on-device before relying on absolute numbers.
