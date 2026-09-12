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
dart run benchmarks/package_overhead_benchmark.dart
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

These are historical JIT measurements. `.each` delegates to the cached
classic loop. `.records` eagerly allocates a list and a record per match;
`snapshot()` is its explicit spelling. Allocation costs vary substantially
between JIT and AOT, so the old 2× ratio is not a general estimate. Prefer
`.each` for frame loops and snapshots when a caller needs fixed membership.

## Package overhead

[`package_overhead_benchmark.dart`](package_overhead_benchmark.dart) measures
queries while unrelated spawn parts await typed registration, event cursor
consumption, and a throwing-cleanup lifecycle probe. The
[2026-09-12 AOT capture](results/2026-09-12-package-overhead-aot-desktop.txt)
records before/after results:

| Operation | Before | After |
| --- | ---: | ---: |
| Empty query, 10,000 unchanged parked parts | 275.33 µs | 99.00 ns |
| Empty query, no parked parts | 81.96 ns | 88.40 ns |
| Consume a 10,000-event batch (cursor operation only) | 9.70 µs | 61.69 ns |

Query scans are cached until new parts arrive; the first typed use after
invalidation still scans the backlog. Event consumption advances the cursor
without copying the batch. These are single desktop measurements, including
timer overhead; they do not predict a rendered frame rate.

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

## Historical scene captures

The scene benchmark application is no longer shipped. The
[`aggregate_scene_benchmark.dart`](aggregate_scene_benchmark.dart) parser
is retained for historical `SCENE_BENCHMARK` logs. For current rendering
performance, profile a representative application such as
[`examples/scene_game`](../examples/scene_game) on its target device.

## Documentation checks

From the workspace root, run `dart run tool/check_docs.dart`. This verifies
relative Markdown links and links into this repository on GitHub, then
extracts fenced blocks marked `dart doc-test:name` and runs their `main()`
functions through `flutter test`. Each marked block must be a standalone
Dart library with its imports. CI runs the same check. Fragment anchors
and external websites are not checked.
