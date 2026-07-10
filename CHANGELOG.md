# Changelog



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
- `WorldOverlay(camera:)` + `WorldAnchor`/`WorldAnchors<T>` — widgets at
  entities' projected positions via a `Flow` delegate; the camera is an
  explicit parameter, the same one you hand `SceneView`.
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
