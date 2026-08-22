# Scene-Dash v2: Concept and Architecture

Scene-Dash is an object-based ECS and feature layer for `flutter_scene`.
Its job is to organize, coordinate, and headlessly test gameplay code as a
game grows; ECS is the implementation model, not a replacement renderer or
scene framework.

It is primarily an ergonomics and architecture project. It does not assume
an ECS or typed-array storage is automatically faster than straightforward
object-oriented Dart; the [benchmarks](../benchmarks) exist to keep that
claim honest.


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

Registration resolves stable handles once:

- a component store is built the first time you insert that type, and
  then it stays
- a system gets its own event cursor (`world.events<T>()`) on its first
  run and keeps it
- a query registers its stores where you write the types, and the loop
  reuses them

One exception. Every `world.query…()` call builds a small view object.
The [benchmarks](../benchmarks) measure it.

## Allocate nothing per matching entity

A hot query allocates nothing per row. No result list, no record, no
copy, no iterator wrapper, no scratch vector, no closure built inside the
loop:

```dart
world.query2<SceneTransform, Velocity>().each((entity, transform, velocity) {
  transform.x += velocity.x * world.dt;
});
```

`.each` is the main form. `for (final (e, t, v) in query.records)`
allocates one record per row, so keep it off the hot path.

## Drive from the smallest store

For a query like:

```dart
world.query2<SceneTransform, Velocity>(require: const [Player])
```

Scene-Dash walks whichever store holds the fewest entities, then checks
the others by lookup. That helps picky gameplay queries. It is not built
for sweeping one big uniform table.

Every extra component in a query is another lookup per entity, so state
that always travels together belongs in one component. Queries stop at
four.

## Avoid duplicated scene data by default

For visual-only state, store a `SceneNode` and mutate the native node
directly. Reach for `SceneTransform` when ECS-owned transforms buy you
something real: serialization, rollback, networking, renderer
independence, or headless simulation.

## Deferred by construction

`spawn`, `despawn`, `add`, `remove` and `ownedBy:` are queued and applied
at the frame boundary, so despawning inside `.each` is safe. If an owned
entity spawns more owned entities, all of it settles in the same
boundary, and `DespawnOnExit`/`DespawnAfter` go the same way. The `*Now`
versions happen immediately. They are for setup code, they live in
`advanced.dart`, and they assert if a query is running.

## Logic on components

A component may carry logic. The boundary: the object computes, the
system performs world effects. A component method never holds or touches
`World`. Holding an `Entity` as data is fine. Machines expose edges.
Systems spawn, emit and mutate on them.

### State at four scales

The same edge vocabulary at every scale:

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

The first four are plain values ticked by their owner system, so they
pause, slow and freeze with the game and never touch the schedule.
Whole-game state is a framework machine because separate features have to
agree on it.

A machine is a mode other systems read. A routine is a plan only its
driver reads. If anything outside the driver branches on where you are,
it is a machine.

### Where state lives

An entity's condition is a component on that entity. An ongoing process
is a component on its own entity, scoped with `DespawnOnExit` like
anything else. A resource is a service you register once, for state where
"two of them" is meaningless: score, indexes, input, shared pools. The
test is "could there ever be two?"

`world.single<T>()` and `singleOrNull<T>()` read a one-of-a-kind
component without a query.

## Access metadata is diagnostic, not enforced

`reads:`/`writes:` on `addSystem` declare which components a system
touches. The scheduler uses this to detect access conflicts between
unordered systems (write/write and read/write) and to validate ordering.

Dart cannot stop you writing to something you declared read-only, and the
scheduler cannot see through a reference. So when a system changes a
node or a Rapier body it reached through a `SceneNode`, declare
`writes: {SceneNode}` anyway. Otherwise the declaration is a lie and the
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
It is off by default and costs nothing off. Turn it on and the
`SystemProfiler` resource keeps a `SystemTiming` record for each one, and
can warn you when a system runs longer than `slowSystemThreshold`.
