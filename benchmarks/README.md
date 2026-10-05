# Scene-Dash v2 benchmarks

These benchmarks measure what the object-based sparse-set design really
costs, and what the v2 record-query shorthand adds on top of the classic
query classes it wraps. They exist to catch regressions and sanity-check
claims, not to sell anything. Queries give you organization and component
selection for a measurable cost per entity. The shorthand gives you nicer
code for a measurable cost per call. Both costs should stay small and
*known*.

## Running

JIT runs are handy while you iterate:

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

For numbers you want to compare over time, build AOT executables with
`dart compile exe`. Desktop numbers, JIT or AOT, only show the rough shape
of CPU cost; check anything about rendering on a real device. Saved runs
are in [`results/`](results/).

## What the record-query shorthand costs

`record_query_benchmark.dart` is the v2-only suite.
`world.query2<A, B>().each(...)` builds a small view on every call. That
view registers stores, picks up spawn parts waiting for their type, and
records types for the access-drift check. Then it hands off to the same
cached loop the classic API uses. Desktop JIT, N = 10k
(`results/2026-07-09-jit-desktop.txt`):

| Measurement | JIT result |
| --- | ---: |
| classic `Query2.each` (construct once, cached) | 9.7 ns/entity |
| record view `.each`, constructed per call | 9.7 ns/entity |
| record view `.records` for-in | 21.0 ns/entity |
| classic `query2(...)` construction alone | ~87 ns/call |
| record `query2(...)` construction alone | ~75 ns/call |

These are older JIT measurements. `.each` hands off to the cached classic
loop. `.records` allocates a list and one record per match up front;
`snapshot()` is the same thing under a clearer name. Allocation costs
differ a lot between JIT and AOT, so do not read the 2× gap above as a
general rule. Use `.each` in frame loops, and a snapshot when you need the
set of matches fixed.

## Package overhead

[`package_overhead_benchmark.dart`](package_overhead_benchmark.dart)
measures three things: queries while unrelated spawn parts wait for their
type to be registered, reading a batch of events, and a lifecycle check
where cleanup throws. The
[2026-09-12 AOT capture](results/2026-09-12-package-overhead-aot-desktop.txt)
records results before and after the fix:

| Operation | Before | After |
| --- | ---: | ---: |
| Empty query, 10,000 unchanged parked parts | 275.33 µs | 99.00 ns |
| Empty query, no parked parts | 81.96 ns | 88.40 ns |
| Consume a 10,000-event batch (cursor operation only) | 9.70 µs | 61.69 ns |

A query's scan result is cached until new parts arrive. The first typed
use after that still scans the waiting parts. Reading events moves the
cursor forward without copying the batch. These are single desktop runs,
timer overhead included. They do not predict a rendered frame rate.

## Suites carried over from v1

The other benchmarks are the v1 core suite, moved onto the v2 low-level
API (`package:scene_dash_v2_core/advanced.dart`). They measure the same
things as before:

- `object_query` — flat `List<Actor>` loops vs sparse `Query1`/`Query2`,
  with and without a tag filter. This is the honesty baseline: the extra
  step through the sparse set costs a few ns per entity over a flat loop.
- `representative` — a game-shaped frame: movement, a player scan, a
  regen pass.
- `spawn_despawn` — cost per entity to record and apply a bundle.
- `structural_churn` — adding and removing components over and over.
- `despawn_store_scaling` — despawn cost as the store count grows.
- `query_entity_allocation` — the entity parameter's cost when ignored
  vs consumed.
- `rts_workload` — movement/state/selection passes plus a spatial-grid
  rebuild and nearby lookups at RTS scale.
- `transform_sync` — full-TRS vs changed-only transform sync.
- `schedule_dispatch` — the fixed cost of running a frame: calling each
  system, `runIf` checks, many separate query runs, event channel
  upkeep.

The v1 AOT capture (2026-06-23, Dart 3.13 dev) still shows the expected
shape: sparse queries ~7 ns/entity vs ~1 ns flat, dispatch ~1.6 ns/system,
and each query run ~15–60 ns fixed plus the per-entity cost. So even with
thousands of query runs per frame, per-entity work dominates, not the
frame overhead. Capture again on your machine before trusting the exact
numbers.

## Old scene captures

The scene benchmark app is no longer shipped. The
[`aggregate_scene_benchmark.dart`](aggregate_scene_benchmark.dart) parser
is kept for old `SCENE_BENCHMARK` logs. For current rendering
performance, profile a typical app such as
[`examples/scene_game`](../examples/scene_game) on the device it targets.
