# Scene-Dash v2: Concept and Architecture

Scene-Dash is an ECS and feature layer for `flutter_scene`, built on plain
Dart objects. Its job is to keep gameplay code organized, coordinated and
testable without rendering as a game grows. ECS is how it is built inside.
It does not replace the renderer or the scene framework.

It is mainly about ergonomics and architecture. It does not assume an ECS,
or typed-array storage, is automatically faster than plain object-oriented
Dart. The [benchmarks](../benchmarks) are there to keep that claim honest.


## Object components

The default component model is an ordinary mutable Dart object:

```dart
final class Velocity {
  double x;
  double y;
  double z;

  Velocity(this.x, this.y, this.z);
}
```

Each object store is a packed sparse set:

```text
entity IDs: [4, 9, 12]
values:     [Velocity(...), Velocity(...), Velocity(...)]
```

A query hands your system the stored object itself, and the system
changes it in place. Nothing is wrapped or copied on the way.

A tag is a component with no data, kept in the same stores. Checking for
one is a single lookup, it holds nothing per entity, and it never uses up
a query slot.

## Cache everything stable

Anything that does not change is looked up once and kept:

- a component store is built the first time you insert that type, and
  then it stays
- a system gets its own event cursor (`world.events<T>()`) on its first
  run and keeps it
- a query registers its stores where you write the types, and the loop
  reuses them

One exception: every `world.query…()` call builds a small view object.
The [benchmarks](../benchmarks) measure what that costs.

## Allocate nothing per matching entity

A hot query allocates nothing per row. No result list, no record, no
copy, no iterator wrapper, no scratch vector, no closure built inside the
loop:

```dart
world.query2<SceneTransform, Velocity>().each((entity, transform, velocity) {
  transform.x += velocity.x * world.dt;
});
```

`.each` is the main form. `for (final (e, t, v) in query.snapshot())`
allocates a list and one record per row up front, so keep it out of hot
loops. It fixes which entities match at the moment you call it, but it
still hands out the live component objects. If a UI selector needs values that will not
change under it, copy the fields.

## Drive from the smallest store

For a query like:

```dart
world.query2<SceneTransform, Velocity>().having<Player>()
```

Scene-Dash walks whichever store holds the fewest entities, then checks
the others by lookup. That suits narrow gameplay queries. It is not built
for sweeping one big table where every entity looks the same.

Every extra component in a query is another lookup per entity, so state
that always travels together belongs in one component. Queries stop at
four.

## Avoid duplicated scene data by default

For state that is only visual, store a `NodeRef` and change the native
node directly. Use `SceneTransform` only when having the ECS own the
transform gives you something real: serialization, rollback, networking,
renderer independence, or simulation without rendering.

## Deferred by construction

`spawn`, `despawn`, `add`, `remove` and `ownedBy:` are queued and applied
at the frame boundary, so despawning inside `.each` is safe. If an owned
entity spawns more owned entities, all of it settles at the same
boundary. `DespawnOnExit` and `DespawnAfter` work the same way. The `*Now`
versions happen immediately. They are meant for setup code, they live in
`advanced.dart`, and they assert if a query is running.

## Logic on components

A component may carry logic. The rule: the object computes, and the system
changes the world. A component method never holds or touches `World`.
Holding an `Entity` as data is fine. Machines report edges (a state just
entered or exited), and systems spawn, emit and change things in response.

### State at five scales

Every scale uses the same edge words:

- **`GameTimer`**: a duration. Cooldowns, windups, cadences.
  `tick(world.dt)`, `finished`, `justFinished` true for exactly one tick.
- **`GameTween<T>`**: a *value* over that duration. A camera move, a hit
  flash, a material fade. `tick(world.dt)`, `value`, `justFinished`, plus
  a curve. `smoothTo` is the version for a target that keeps moving.
- **`Machine<S>`**: an entity's *mode*. Idle, charging, rolling.
  `tick(world.dt)`, `elapsed`, `go`, with `justEntered`/`justExited` true
  for exactly one tick-window.
- **`Routine<L>`**: a *sequencer*. A wave director, an objective, an
  encounter. `advance(world.dt, run)`, `current`, `elapsed`, and the
  driver answers `running` / `success` / `failure` per step. The sequence
  is a `const`, so one plan drives every entity running it.
- **Whole-game state machines** (`addState<S>`): title, playing, lost.
  Transitions apply at frame boundaries, `OnEnter`/`OnExit` are
  schedules, `inState(...)` is the run condition.

The first four are plain values that their owning system ticks, so they
pause, slow down and freeze with the game and never touch the schedule.
Whole-game state is a framework machine because separate features have to
agree on it.

A machine is a mode that other systems read. A routine is a plan that only
its driver reads. If anything outside the driver makes decisions based on
where you are, it should be a machine.

### Where state lives

An entity's condition is a component on that entity. An ongoing process
is a component on its own entity, cleaned up with `DespawnOnExit` like
anything else. A resource is a service you register once, for state where
"two of them" makes no sense: score, indexes, input, shared pools. Ask
"could there ever be two?" If not, it is a resource.

`world.single<T>()` and `singleOrNull<T>()` read a one-of-a-kind
component without a query.

## Access metadata is checked, not enforced

`reads:` and `writes:` on `addSystem` declare which components a system
touches. The scheduler uses them to find conflicts between systems that
have no set order (two writers, or a reader and a writer) and to check
ordering.

Dart cannot stop you writing to something you declared read-only, and the
scheduler cannot see through a reference. So when a system changes a
node or a Rapier body it reached through a `NodeRef`, declare
`writes: {NodeRef}` anyway. Otherwise the declaration is a lie and the
diagnostics go with it.

Declaring is optional. Leave both off and the detector ignores the
system. `boot(strictAccess: true)` makes that an error instead. Debug
builds also warn when what you declared drifts from what your queries
actually use.

The detector only looks at types, not entities. Two systems on completely
different entities, or on different fields of one component, still look
like a conflict to it. When you know a pair is fine,
`independentOf: [other]` excuses just that pair.

## Optional system profiling

`AppDiagnostics(profileSystems: true)` times every system, per schedule.
It is off by default and costs nothing while off. Turn it on and the
`SystemProfiler` resource keeps a `SystemTiming` record for each one, and
can warn you when a system runs longer than `slowSystemThreshold`.
