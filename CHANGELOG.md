# Changelog

## Unreleased

### The "Now" campaign (work units on top of the v2 rewrite)

- Component observers (surface tier): `GameBuilder.observe<T>({onAdd,
  onRemove})` — explicit per-feature callbacks fired during the
  command-boundary flush, immediately after the change applies; despawn
  fires `onRemove` per stripped component; add-over-existing fires
  nothing (no `onChange`, deliberately). Observer bodies may use the
  deferred verbs and `emit` (same flush) but not `events<T>()`.
- Timed component removal (surface tier): `world.add(entity, component,
  removeAfter: seconds)` — fixed-step game time (pause/hitstop consume
  nothing), deferred removal at the step's boundary, `expiryOf<T>` for
  the time remaining; re-add refreshes, manual remove cancels, despawn
  invalidates generationally. Plus `world.single<T>()`/
  `singleOrNull<T>()` — component singletons unwrapped, the ergonomics
  behind the state doctrine (see `docs/concept.md`).
- `Machine<S>` (surface tier): the mode primitive beside `GameTimer` —
  `state`/`elapsed`/`tick`/`go`, with `justEntered`/`justExited` edges
  true for exactly one tick-window (`justFinished` semantics for modes).
  A plain value type on components, never registered, ticked with
  `world.dt`, so it pauses and freezes with the game. `debugDescribe`
  prints a component's own `toString` when overridden (a `Machine`
  renders as `charging (0.42s)`). Proven by the frame-exact souls-style
  combat reference suite (hitstop-shift and determinism included).
- `Disposable` resources (surface tier): `abstract interface class
  Disposable { void dispose(); }` — no base class, no registration. The
  framework disposes an implementing resource at exactly three points,
  once per instance: game shutdown (reverse insertion order — dependents
  die before dependencies), `World.reset(keepResources: false)` for the
  dropped resources, and removal/replacement for the outgoing instance.
  `Resources.clear()` is replaced by `disposeAll()`. Blocs need nothing
  more than `implements Disposable { void dispose() => close(); }`.
- Inspector (wave 1): `InspectorSnapshot` + `SnapshotCollector` in core
  diagnostics (exported via `advanced.dart`) — plain-data views of
  entities (type names in summaries, `debugDescribe` values on
  selection only), resources, profiler timings and event channels; and
  the new optional `scene_dash_inspector` package with
  `InspectorOverlay({visible})`, a read-only `Stack` panel polling
  snapshots at 4 Hz (configurable), zero cost hidden. The snapshot
  boundary is the same data a DevTools frontend consumes in wave 2.
- Nested-query diagnostic (debug mode): a query iteration beginning
  while another is active in the same system — the accidental O(N×M)
  shape — is reported once per system through the diagnostics sink,
  with both query spellings and the row-count product. Tracking sits
  inside asserts; release builds compile it out.

### The authoring surface (new)

- Systems are stateless `void Function(World world)`; registration is
  `GameBuilder.addSystem(schedule, fn, {reads, writes, before, after,
  runIf, inSet, label})`. A system's identity is its function reference —
  `after: [locomotion]` is a tearoff, and a rename is a compile error.
- Features are plain functions over the **one builder** (`GameBuilder`:
  `addSystem`, `addState`, `configureSets`, `configureEvent`,
  `registerComponent`/`registerTag`, `world`, `addPlugin` for classic
  interop). No nested builders.
- Record queries: `world.query<A>()` … `query4<A, B, C, D>` with
  `require:`/`exclude:`, `.each` first (allocation-free), `eachUntil`,
  `any`/`firstWhere`, `first`/`firstOrNull`/`single`/`singleOrNull`,
  `isEmpty`/`isNotEmpty`, `count()`, and a `records` iterable for for-in.
- World surface: `dt` (schedule-aware), `delta`/`fixedDelta`, `clock`,
  `emit`/`events<T>()` (per-registration cursors, framework-managed),
  `setState`/`state<T>()`, `spawn(parts, ownedBy:)`/`despawn`/`add`/
  `remove` (deferred), `buttons<A>()`/`axes<A>()`/`buffer<A>()`,
  `entitiesWith`, `gizmos`, `physics`.
- Bundles are functions returning `List<Object>`; composition is a
  spread; `ownedBy:` ties subtree lifetimes to their owner.
- `hasResource<T>()` run condition — gate a system on an optional
  capability (`runIf: hasResource<Scene>()` skips visual spawners on
  headless boots) instead of an early-return guard in the body.
- Access declarations (`reads:`/`writes:`) feed the carried conflict
  detector; omitting both excludes the system, `strictAccess: true` makes
  that an error, and a debug drift check compares declarations against
  queried types.
- `Tag` marker interface for bitset-stored tags.
- `TestGame.headless` — the device frame pipeline, exactly, with no scene
  and no GPU: `pump`/`pumpFixed`/`press`/`emit`.

### The Flutter layer (new)

- `SceneGame.boot(scene:, physics:, features:, strictAccess:)`, with a
  non-null `scene` — modes are types (D13): a widget tree over a
  scene-less world boots `WorldGame` instead, and pure-logic suites boot
  the core `TestGame`. The framework never constructs or wraps
  `SceneView` — the widget tree, the camera, and focus are yours;
  `game.onTick` drives the loop.
- `GameScope`/`GameHost` + `context.game`/`context.world`.
- Reactive primitives on one `frameTick` heartbeat with
  select-and-compare: `EntityBuilder<T, S>`, `WorldBuilder<S>`,
  `GameStateBuilder<S>`, `WorldEventListener<E>`, plus the
  `WorldInspector` debug widget.
- Debug gizmos are opt-in (`installGizmos(enabled: ...)` in the feature
  list — boot never adds them implicitly), and `Gizmos.enabled` is a true
  runtime toggle: pools build lazily on the first enabled frame and hide
  when it goes off. Without the feature, `world.gizmos` is a disabled
  recorder, so submission calls in shipping code stay safe no-ops.

### Renames and carried semantics

- `SceneNodeRef` → `SceneNode`.
- `Schedules.fixedPrePhysics` → `Schedules.fixedUpdate` (alias; the old
  label remains valid).
- `every()` and `world.dt` are schedule-aware: fixed delta inside fixed
  schedules, frame delta elsewhere.
- Event channels: unchanged v1 semantics, plus `readerFromStart()` so a
  cursor created lazily at a system's first run still sees events sent
  just before it, and reader-less bounded channels now expire by their
  retention window instead of dropping everything at maintenance.
- Classic machinery — arity query classes, `Single`/`OptionalSingle`,
  `EntityQuery`, `Commands`, immediate `*Now` verbs, `App`/`AppBuilder`/
  `Plugin`, `EcsFrameLoop`, `SystemAdapter`, stores — moved to
  `advanced.dart` (documented in the library itself). Nothing is silently
  absent — every v1 feature maps to the surface, the machinery tier, or a
  named replacement.

### Removed (by design, without successor)

- `@System`, `@Query`, `@Resource`, `@GamePlugin`, `@Bundle`,
  `@ObjectComponent`, `@Tag` annotations; the generator package;
  `build_runner` and every `.g.dart`.
- `Plugin` as the gameplay authoring shape (kept in `advanced.dart` as a
  migration escape hatch only).
- `Game.dispatch` → `game.emit`/`world.emit`.
- `WorldOverlay`/`WorldAnchor`/`WorldAnchors<T>` (and the `camera:`
  same-box contract) — flutter_scene 0.19's GPU-resident
  `WidgetComponent` makes the scene graph the anchor system: a widget on
  a child node is positioned, projected, occluded and despawned by
  machinery that already exists. A parallel projection layer
  re-implemented what the scene already does.
