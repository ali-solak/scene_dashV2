# Changelog

## Unreleased

### Surface

- `world.previousState<S>()` — the transition's other side (null before
  the first), surfacing the `CurrentState.previous` the machine already
  tracked. An OnEnter system tells a resume from a fresh run without a
  hand-rolled flag: the combat sample's `RunControl.resetPending` is
  deleted; `startRun` gates on `previousState == skillMenu`.
- setState-from-a-fixed-step semantics pinned by test: the transition
  applies at the NEXT frame boundary — deferred, never lost (the old
  "does not take" trap was a pumpFixed artifact, gone since pumpFixed
  became the full per-frame pipeline). The sample's stale comment is
  corrected.
- `WorldBuilder(equals:)` (widget layer, both forms) — overrides `==`
  for the change compare, so a select can return a plain `List` with
  `listEquals` instead of a hand-written value class; the skill bar's
  `_SkillSlots` class is now a record.
- `addSystem(..., independentOf: [systems])`: pairwise access-conflict
  exemption, by function reference: the author asserts the listed pairs
  are independent (disjoint entities, or different fields of one
  component — what the entity-blind detector cannot see), and detection
  skips exactly those pairs, both directions. Ordering is untouched and
  every other pairing keeps the full net. Replaces the combat sample's
  fake `after:` edges on `lockOnSystem`.
- Input buffers age themselves: the frame drivers advance every
  `InputBuffer` resource by `FrameTime.unscaledDelta` once per frame,
  before `frameStart` — the hand-installed aging system (forgettable,
  silently leaving the press window infinite) is gone. `autoAdvance:
  false` opts out for custom clocks; `advance()` stays public.
- `world.expiryOf<DespawnAfter>` reads the component's own clock instead
  of returning null, so both timed-lifetime mechanisms answer through
  the one call (kills the lava-pit dead-end in the combat sample).
- `world.unscaledDelta` — the wall-clock delta promoted beside
  `world.delta`/`world.fixedDelta`, for HUD/camera-shake systems that
  keep moving through pause, slow motion and hitstop.
- The S6 observer cascade guard counts per (type, entity), not per-type
  volume: adding an observed component to a whole pack in one flush (a
  fire gush catching twenty barbarians) no longer throws in debug; a
  same-entity re-add/re-remove loop still trips at the same limit.
- `Resources.values` — allocation-free sibling of `entries` for
  per-frame sweeps (the buffer aging uses it).
- `WorldBuilder.pulse` (widget layer). the transition-to-pulse form: the
  frame `trigger(previous, next)` passes on a changed selection,
  `pulseBuilder` receives a pulse decaying 1 → 0 over `duration` 
- `world.consumeAny<E>()`  the boolean shape of `world.events<E>()` for
  edge-like signals: reports whether any events arrived since this
  system's last read, consuming them (same per-registration cursor).
  Driven by four call sites in the example game and the README's fighter;
  logged in NOTES.md as the core-surface moratorium exception.
- `EntityQuery.firstOrNull`  the entity-query counterpart of the record
  queries' `firstOrNull`, replacing the `firstWhere((entity) => true)`
  workaround (API-asymmetry repair).
- `EntityBuilder.matching` (widget layer) — watches the first entity
  carrying `T` + `require:` filters, re-resolved through the world each
  frame: no `Entity` handle crosses into the widget tree, one `absent`
  covers no-match/death/respawn, and a respawned entity is picked up
  automatically. Replaces the nested `WorldBuilder<Entity?>` +
  `EntityBuilder` resolve-then-watch at both existing call sites; the
  composition remains only for resolving by one component while watching
  another.

### The "Now" campaign (work units on top of the v2 rewrite)

- Component observers (surface tier): `GameBuilder.observe<T>({onAdd,
  onRemove})`  explicit per-feature callbacks fired during the
  command-boundary flush, immediately after the change applies; despawn
  fires `onRemove` per stripped component; add-over-existing fires
  nothing (no `onChange`, deliberately). Observer bodies may use the
  deferred verbs and `emit` (same flush) but not `events<T>()`.
- Timed component removal (surface tier): `world.add(entity, component,
  removeAfter: seconds)`  fixed-step game time (pause/hitstop consume
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

### The flutter_sce

- Gizmos render on upstream meshes (U7): the sphere pools moved to
  0.19's geodesic `IcosphereGeometry` (one subdivision — 80 evenly
  distributed triangles, rounder than the old low-segment UV sphere at
  the same debug-grade cost). Line/ray gizmos deliberately stay
  stretched instanced cuboids: 0.19's `LineSegmentsGeometry` bakes its
  endpoints into a GPU buffer at construction with no update path, so an
  immediate-mode layer would have to rebuild geometry (and allocate a
  device buffer) every frame — breaking the layer's
  no-per-frame-allocation contract. Revisit when upstream ships an
  updatable segment batch (backlog). The public gizmo API is unchanged;
  a new heavy-frame test pins staging at hundreds of shapes per frame.
- scene_game's hand-rolled particle simulations are gone (U6): flaming
  rock trails, impact flashes and shield-deflection bursts now render
  through upstream `ParticleEmitterComponent`s — the `Flaming` observer
  pair attaches/removes a trail emitter node (its real payload; the
  `RockTrails` resource and per-frame re-lay system are deleted,
  superseding the observers-era note that kept it as the doctrine
  counter-example), and impacts and deflections spawn short-lived burst
  entities cleaned up by `DespawnAfter` + `DespawnOnExit`. Every emitter
  carries an explicit `seed:`, so replays are visually identical, and
  emitters advance with the scene tick — sparks freeze under hitstop,
  the clock guarantee demonstrated by the game. `ImpactVfx` and
  `ShieldDeflectVfx` are deleted. The particle API is not yet in
  flutter_scene's public barrel, so `fx/particles.dart` is the game's
  single implementation-import surface (drops when upstream barrels it
  — backlog).
- Emitter sprites are textured with a shared soft radial-falloff dot
  (`fx/particle_texture.dart`) so trail/impact/deflect particles read as
  glowing orbs, not the hard squares an untextured `SpriteMaterial`
  draws (the deliberate visual pass, U5).
- The charge-up VFX stays a hand-animated node effect, not an emitter
  (U5): a cone emitter read as a flat spray and lost the signature
  swirl, so the charge keeps its original orbiting-mote twirl. Emitters
  win for stochastic bursts and trails; deterministic, shaped motion
  like this reads better hand-driven.
- Hand-rolled meshes replaced by 0.19 primitives: the charge beam is a
  real `CylinderGeometry` (the old file carried "0.18 has no cylinder
  primitive"), and the hand-built impact ring geometry is deleted with
  the pooled impact system (the burst look absorbs it).
- **Device fix (Impeller Vulkan / Mali, e.g. Pixel 8):** the ambient
  decor motes moved off a PBR `InstancedMesh` to individual PBR nodes.
  A physically-based `InstancedMesh` drawn through the lit/shadow/IBL
  passes device-loses the Impeller Vulkan backend on Mali GPUs (a
  `pthread_mutex` abort in the driver's fence thread, surfacing as a
  failed `ResolvePass` command-buffer submit); the same geometry as
  discrete nodes — like every other PBR object in the scene — renders
  fine. `fx/instanced_pool.dart` is deleted (decor was its last
  consumer). Unlit `InstancedMesh` is unaffected, so the debug gizmo
  pools keep instancing.

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
