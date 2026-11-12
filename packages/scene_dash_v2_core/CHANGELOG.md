# Changelog

## 0.7.0
- `Entity` is an extension type over one `int` (24-bit index, 29-bit
  generation, packed within 53 bits so it is exact on the web). Queries no
  longer allocate a handle per row: `Query1.each` 5.0 → 3.8 ns/entity AOT.
  `'$entity'` prints the packed number; use `entity.label`. Spawning past
  `Entity.maxIndex` live slots throws a `StateError`.
- The classic query constructors are `rawQuery1`..`rawQuery4`, so
  `advanced.dart` exports the record `query`..`query4` without a clash.
- Debug builds assert when a store would split a type: creating a store
  for a type whose supertype or subtype already has one. Read the subtype
  through the supertype's store (`tryGet`, `has`, `handle`) instead.
- `GameBuilder.addSystems(schedule, [(system, reads:, writes:), ...],
  runIf:, inSet:, chain:)` registers several systems in one call; each
  entry keeps its own access, and `chain: true` runs them in list order.
- `GameBuilder.group(runIf:, inSet:, (game) {...})` shares a run condition
  (AND-ed with each system's) and a set across the systems it registers.
- A system that can only be named `closure@N` (closures, web, obfuscated
  builds) is reported once, pointing at `label:`.
- `world.handle<T>()` resolves a store once for `of`/`get`/`has` lookups
  inside loops.
- `world.eachEvent<E>(callback)` reads events without allocating.
- `ButtonInput.justPressed`/`justReleased`: one frame in update systems,
  one step in fixed systems, so a fixed system never misses or repeats an
  edge on frames with zero or several steps. `ButtonInput.cancel` lets go
  without a release edge (`ButtonEdge.canceled`). `advanceInputBuffers` is
  now `advanceInput`; `beginInputStep`/`endInputStep` bracket a fixed step.
- `FixedTime.alpha`: the fraction of a fixed step left over this frame.
  `EcsFrameLoop` takes `onFixedStepStart`, and `update` takes `fixedAlpha:`.
- `World` caches `frameTime`, `fixedTime`, `clock`, `spawnQueue` and
  `removeAfterTracker`, so `dt`, `add`, `remove` and `spawn` skip the
  resource lookup. The spawn-queue and tracker getters are `@internal`.
- `RemoveAfterTracker` indexes rows per entity; `add(removeAfter:)`,
  `remove` and `expiryOf` no longer scan every tracked row.
- The parked-part diagnostic names `ensureStore<T>()` instead of the removed
  `registerComponent<T>()`.

## 0.6.1
- minor perf upgrades

## 0.6.0
- Stores create themselves on first use: spawning, `add<T>`, any type
  argument. `registerTag` and `registerComponent` are gone.
- Typed filters: `.having<T>()` / `.without<T>()` on query views and
  `world.entitiesWith<T>()`. The `require:`/`exclude:` `Type` lists are gone.
- `.records` is gone; use `snapshot()`.
- `emit<E>` delivers to the event's own class channel when one exists,
  otherwise to the channel of `E`, so `emit<GameEvent>(EnemyKilled())`
  reaches `events<GameEvent>()` readers instead of throwing, and
  `emit(c ? A() : B())` still reaches `events<A>()` / `events<B>()`.
- `world.add` is generic and creates the store of its static type when that
  is the component's exact type.
- `get`, `tryGet` and `has` see components no query has named yet, and read
  subtypes from their supertype's store without splitting it.
- Waiting spawn parts are claimed when their store is created, never during
  a running query and never through observers.
- A part with no exact store goes straight into a registered supertype store.
- `spawn` and `add` assert against `Type`, function, `Future` and `Iterable`
  parts (`spawn([Enemy])`, `Enemy.new`, nested lists).
- Despawn visits only the entity's stores once a world has more than 10, so
  its cost no longer grows with the number of component types.
- Add `QueryView.revision`, `World.ensureStore<T>()`,
  `World.ensureEventChannel`, store change listeners
  (`addChangeListener`/`removeChangeListener`), `StoreRegistry.onCreated`,
  `lookup`, `count`, `storeAt` and `StoreMembership`.
- `SpawnQueue.ensureStore` and `world.entitiesWith(require:)` are gone.

## 0.5.4
- Add `QueryView1.get(entity)`: the component when the entity matches the
  query, or `null`.

## 0.5.3
- Fix a command flush replaying applied commands (or throwing `RangeError`)
  when an observer runs a schedule mid-flush. A nested `Commands.apply` now
  returns and the outer flush drains the queue.
- Fix `world.remove<T>` asserting when the entity was despawned earlier in
  the same flush.
- Fix `Routine` settling the whole plan when an empty child `Sequence` or
  `Select` is entered; it now reports to its parent like any other child.
- Allow a chain of exactly `App.maxStateTransitionPasses` transitions.
- `World.reset` now clears pending `removeAfter` deadlines.
- Store `removeAfter` generations unsigned, matching entity generations.
- Guard despawn against stores registered by observers mid-despawn.
- Skip query type bookkeeping in release builds; empty `events<T>()` reads no
  longer allocate.
- Assert a positive duration when resetting a repeating `GameTimer`.
- Remove unused `World.debugEventChannels`,
  `EventChannelMaintenance.readerLagged` and `StateMachine.stateType`.
- Point error messages at `configureEvent<T>()` and drop references to the
  removed `@Resource()` injection.

## 0.5.2
- Cache parked-component scans until new parts arrive; explicit component
  registration claims waiting parts, and despawn/reset release unclaimed parts.
- Use weak identity tracking for disposed resources. Shutdown attempts all
  cleanup callbacks and resources, then reports a `CleanupException` containing
  the original exceptions and stack traces.
- Make `consumeAny` use a constant-time cursor advance without a result list.
- Add `EventReader.dispose()` and release system readers on shutdown.
- Add `snapshot()` to query views; `.records` remains an eager allocating alias.
- Resolve function-based system ordering at boot, allowing references to later
  features. Validate missing and cross-schedule references, including
  `independentOf` when conflict detection is disabled.
- Check local documentation links and compile runnable Markdown examples in CI.

## 0.5.1
- a variety of ordering fixes for events and command buffers

## 0.5.0
- upgrade deps

## 0.4.0
- upgrade deps

## 0.2.0
- adds new routine mechanism for better organizing sequenced game logic

## 0.1.3
- adds custom schedules feature

## 0.1.2

- minor fixes for pub dev

## 0.1.0

First release.
