# Scene-Dash v2 — Concept and Architecture

Scene-Dash is an object-based ECS and feature layer for `flutter_scene`.

It is primarily an ergonomics and architecture project. It does not assume
an ECS or typed-array storage is automatically faster than straightforward
object-oriented Dart — the [benchmarks](../benchmarks) exist to keep that
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

Queries hand systems direct references to the stored objects, and systems
mutate those objects in place. There is no per-result wrapper, copy, or
record on the hot path.

Tags implement the `Tag` marker and are stored as bitsets — filtering on
one is a bit test, and `require:`/`exclude:` never cost a query slot.

## Cache everything stable

Registration resolves stable handles once:

- component stores register lazily on first insert and are then permanent;
- a system's event cursor (`world.events<T>()`) is created at its first
  run and memoized per registration;
- query construction registers its stores at the typed site and the
  iteration driver reuses them.

A frame should not repeatedly perform service lookup, reflection, or
channel registration. (One deliberate exception: a record query view is
constructed per `world.query…()` call — it is a thin façade over the
cached machinery, and the [benchmarks](../benchmarks) price it.)

## Allocate nothing per matching entity

Hot queries avoid result lists, per-entity records, component copies,
iterator wrappers, temporary vectors, and closures created inside the
inner loop. The target loop stays simple:

```dart
world.query2<SceneTransform, Velocity>().each((entity, transform, velocity) {
  transform.x += velocity.x * world.dt;
});
```

`.each` is the primary spelling for exactly this reason. The record form —
`for (final (e, t, v) in query.records)` — allocates one record per row
and is the documented cold-path alternative, not the default.

The same discipline runs through the integration: `NodeTransformOps`
mutates node matrices in place, gizmo submissions write plain floats into
instanced pools, and per-frame systems keep scratch vectors at file scope.

## Drive from the smallest store

For a query like:

```dart
world.query2<SceneTransform, Velocity>(require: const [Player])
```

Scene-Dash iterates whichever positive store has the fewest members, then
checks the rest through sparse arrays. This helps selective gameplay
queries; it is not aimed at broad homogeneous table iteration.

It is also why composites beat fragments here, unlike in archetype ECSes:
fewer components per query means fewer sparse lookups per entity, so state
that always travels together belongs in one component, and queries stop at
four slots by design.

## Avoid duplicated scene data by default

Duplicating every node transform into ECS state and syncing it every frame
is not always the best default. For visual-only state, store a `SceneNode`
and mutate the native node directly. Reach for `SceneTransform` (ECS-owned
transforms) when that state actually buys serialization, rollback,
networking, renderer independence, or headless simulation.

## Deferred by construction

The structural verbs — `spawn`, `despawn`, `add`, `remove`, `ownedBy:` —
are command-buffered and flushed at frame boundaries, so despawning inside
`.each` is safe by construction rather than by care. Owned-spawn chains
resolve to a fixpoint in one boundary, and `DespawnOnExit`/`DespawnAfter`
ride the same path. The immediate `*Now` variants exist for setup code and
live in `advanced.dart` with their no-active-query asserts.

## Components may bear logic — the boundary rule

Components may bear logic. The boundary: the object computes, the system
performs world effects. A component method never holds or touches
`World`; holding an `Entity` as data is fine. Machines expose edges;
systems spawn, emit and mutate on them.

### State at three scales

The same edge vocabulary at every scale:

- **`GameTimer`** — durations inside gameplay (cooldowns, windups,
  cadences): `tick(world.dt)`, `finished`, `justFinished` true for
  exactly one tick.
- **`Machine<S>`** — an entity's *mode* (idle / charging / rolling):
  `tick(world.dt)`, `elapsed`, `go`, with `justEntered`/`justExited`
  true for exactly one tick-window.
- **Whole-game state machines** (`addState<S>`) — title / playing /
  lost: transitions applied at frame boundaries, `OnEnter`/`OnExit` as
  schedules, `inState(...)` as the run condition.

Timers and machines are plain values ticked by their owner systems, so
they pause, slow and freeze with the game and add nothing to the
schedule; whole-game state is a framework machine because independent
features must coordinate on it.

### Where state lives — the doctrine

An entity's condition is a component on that entity; an ongoing process
is a component on its own process entity (run-scoped with
`DespawnOnExit` like anything else); a resource is reserved for state
where "two of them" is meaningless — score, indexes, input, shared
pools. The test is "could there ever be two?" A singleton that names an
entity's condition or a feature's process is a component in exile.

`world.single<T>()`/`singleOrNull<T>()` make component-singletons as
ergonomic as the resources they replace; observers and `removeAfter:`
carry the lifecycle work (activation VFX, timed expiry) the resource
version hand-rolled.

## Access metadata is diagnostic, not enforced

`reads:`/`writes:` on `addSystem` declare which components a system
touches. The scheduler uses this to detect access conflicts between
unordered systems (write/write and read/write) and to validate ordering.

Dart cannot prevent mutation through an object declared read-only, and the
scheduler cannot infer transitive mutations: when a system mutates a
native object reached through a component reference (a `flutter_scene`
node or a Rapier body behind a `SceneNode`), declare `writes: {SceneNode}`
so the metadata stays honest. Scene-Dash runs schedules sequentially, so
these declarations drive diagnostics rather than a borrow checker.

Declarations are optional: omitting both marks the system *undeclared* and
excludes it from detection. `boot(strictAccess: true)` turns undeclared
into an error for projects that want the full net, and a debug-mode check
compares declared access against the component types the system's queries
actually construct, warning on drift.

## Optional system profiling

System execution can be measured per system and per schedule via
`AppDiagnostics(profileSystems: true)`. Profiling is off by default and
adds no per-system work when disabled. When enabled, the `SystemProfiler`
resource keeps a reusable `SystemTiming` record per (system, schedule)
pair — run count, total/latest/maximum duration, last frame — keyed by the
system's identity (its function reference, or the `label:` override) plus
the schedule it ran in, and can warn when a system exceeds a configured
`slowSystemThreshold`.
