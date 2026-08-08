# Reference

The full API surface

- UI
  - [World-reactive widgets](#world-reactive-widgets)
    - [GameScope](#gamescope)
- Boot
  - [Application setup](#application-setup)
  - [Features and systems](#features-and-systems)
- World
  - [Components, tags, bundles](#components-tags-bundles)
  - [Queries](#queries)
  - [Node lookups](#node-lookups)
  - [Resources](#resources)
- Frame
  - [Scheduling: sets and run conditions](#scheduling-sets-and-run-conditions)
  - [Custom schedules](#custom-schedules)
  - [Time](#time)
- Coordination
  - [Events](#events)
  - [Input](#input)
  - [States](#states)
  - [Machine](#machine)
- flutter_scene
  - [Physics](#physics)
  - [The rendering bridge](#the-rendering-bridge)
- Tooling
  - [Debugging](#debugging)
    - [Entity debug](#entity-debug)
    - [Gizmo debug](#gizmo-debug)
    - [Inspector](#inspector)
  - [Testing](#testing)

## World-reactive widgets

A widget selects one value from the world and rebuilds only when it
changes:

```dart
final player = world.spawn(playerBundle());    // spawn returns the Entity;
                                               //   Health: a plain class
EntityBuilder<Health, double>(
  entity: player,
  select: (h) => h.current,                    // compared per frame; rebuild
  builder: (context, hp) => HealthBar(hp),     //   only on change
  absent: const RespawnCountdown(),            // entity dead / component gone
)
```

The siblings share the same heartbeat and the same select-and-compare:

```dart
WorldBuilder<int>(select: (w) => w.query<Health>(require: const [Enemy]).count(),
    builder: (ctx, n) => Text('$n enemies'))       // any world-derived value

GameStateBuilder<GameStatus>(builder: (ctx, s) => switch (s) { ... })
                                                   // a subtree per game state

WorldEventListener<EnemyKilled>(onEvent: (ctx, e) => shakeScore(ctx),
    child: const ScorePanel())                     // world events into UI;
                                                   //   widget-lifetime cleanup

WorldBuilder<double>.pulse(
    select: (w) => playerHp(w),                    // transient feedback: the
    trigger: (previous, next) => next < previous,  //   frame this passes,
    duration: 0.4,                                 //   pulse runs 1 → 0 over
    pulseBuilder: (ctx, pulse, child) =>           //   wall time (pause never
        HurtVignette(intensity: pulse * pulse))    //   freezes feedback), then
                                     //   rests at 0. Key it off the OUTCOME
                                     //   (the value moved): events also fire
                                     //   for blocked/i-framed hits

WorldBuilder<int>(select: countAmmo, builder: ..., every: Duration(seconds: 1))
                                     // escape hatch: a heavy select polls on a
                                     //   wall-clock interval, not every frame
```

When a feature spawned the entity (nothing in `main` holds the handle),
`.matching` resolves it through the world instead:

```dart
EntityBuilder<Health, double>.matching(
  require: const [Player],            // the first entity with Health + Player,
  select: (h) => h.current,           //   re-resolved each frame; a respawned
  builder: (context, hp) =>           //   player is picked up automatically
      HealthBar(hp),
  absent: const RespawnCountdown(),   // no match, dead, or Health gone
)
// resolving by one component while watching another stays the composition:
// WorldBuilder<Entity?> (resolve) wrapping EntityBuilder (watch)
```

A widget *in* the 3D world (a health bar above an enemy) is not a
framework concern: put a `flutter_scene` `WidgetComponent` on a child
node and the scene graph positions, projects and occludes it.

Write path: UI → `ButtonInput` / `game.emit`. Widgets never mutate
components.

### GameScope

One `InheritedWidget` over the tree; every widget below it reaches the
game from its own `context`, so nothing is threaded through constructors:

```dart
runApp(GameScope(game: game, child: const MyGameApp()));

class PauseButton extends StatelessWidget {                 // const: no
  const PauseButton({super.key});                           //   callbacks in

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: () => GameScope.of(context).emit(const PauseRequested()),
    child: Text('score ${context.world.resource<Score>().value}'),
  );                             // context.world / context.game: the same
}                                //   lookup, one-off reads (not reactive;
                                 //   for that use the builders above)
```

`GameScope.of(context)` is the whole API. `GameHost` is the same widget
plus the hot-reload hook.

## Application setup

```dart
final input = ButtonInput<PlayerAction>();     // the key handler writes it

final physics = RapierWorld.ensureInitialized();   // Rapier loads its wasm;
await physics;                                     //   package flutter_scene_rapier

final game = await SceneGame.boot(
  physics: PhysicsWorld(RapierWorld(gravity: Vector3(0, -9.81, 0))),
  features: [
    (game) {
      game
        ..addState<GameStatus>(GameStatus.playing)   // whole-game mode machine
        ..configureSets(Schedules.fixedUpdate,       // cross-feature phase
            [GameSets.movement, GameSets.combat])    //   order, declared once
        ..world.insert(input)
        ..world.insert(Score());
    },
    installArena,                              // yours: floor + lights
    installPlayer,
    installEnemies,
    installRules,
    installGizmos(enabled: kDebugMode),
  ],
);

runApp(GameHost(game: game, child: const MyGameApp()));   // yours; the
                            // subtree reaches `game` through GameScope.of
```

## Features and systems

A feature registers its systems; a system is a stateless
`void Function(World)`, and every type it touches appears in a query
signature or on a `world.` call.

```dart
const enemyCloseSpeed = 1.5;

void installEnemies(GameBuilder game) {
  game
    ..registerTag<Enemy>()
    ..registerTag<Stunned>()
    ..addSystem(Schedules.fixedUpdate, closeIn,
        writes: {SceneTransform},            // access declaration for the
                                             //   conflict detector
        inSet: GameSets.movement,            // ordered against other features
        runIf: inState(GameStatus.playing))  // skipped while not playing
    ..addSystem(Schedules.fixedUpdate, enemyAttacks,
        writes: {EnemyAttack}, inSet: GameSets.combat,
        runIf: inState(GameStatus.playing));
}

// enemies advance on their target: one query, one mutation, world.dt
void closeIn(World world) {
  world.query2<SceneTransform, Target>(
      require: const [Enemy], exclude: const [Stunned])   // stunned: frozen
      .each((entity, transform, target) {
    final prey = world.tryGet<SceneTransform>(target.entity);
    if (prey == null) return;
    final dir = (prey.translation - transform.translation).normalized();
    transform
      ..x += dir.x * enemyCloseSpeed * world.dt
      ..z += dir.z * enemyCloseSpeed * world.dt;
  });
}
```

```dart
// cheatsheet: every schedule slot
game.addSystem(Schedules.startup, spawnArena);       // once, at boot
game.addSystem(Schedules.frameStart, pollGamepad);   // each frame, before the
                                                     //   fixed steps
game.addSystem(Schedules.fixedUpdate, closeIn);      // 0..N times per frame at
                                                     //   the fixed timestep;
                                                     //   gameplay lives here
game.addSystem(Schedules.postPhysics, readContacts); // after each physics step
game.addSystem(Schedules.update, evaluateGameRules); // once per rendered frame
game.addSystem(Schedules.renderSync, aimCameraRig);  // last before the scene
                                                     //   syncs and draws
game.addSystem(Schedules.shutdown, saveHighScore);   // once, at dispose
game.addSystem(OnEnter(GameStatus.playing), startRun);   // on the transition
game.addSystem(OnExit(GameStatus.playing), stopMusic);   //   frame, one-shot
```

Spawn/despawn/add/remove are deferred to the frame boundary, so
structural changes never break a running query.

## Queries

`closeIn` already shows the whole iteration surface: `require:`/`exclude:`
shape the match set; `.each` hands components to a callback,
allocation-free (`return` = continue, `eachUntil` = break); and a held
`Entity` (`Target.entity`, plain data on a component) resolves in O(1)
with `tryGet`, degrading to a safe `null` when the target despawned or
its slot was reused.

```dart
final class Target {           // Entity is a value type: store it on
  final Entity entity;         //   components, carry it in events
  Target(this.entity);
}
```

```dart
// cheatsheet: building queries. Four arities, each an iterable of
// (entity, components...) rows over entities that have ALL listed types
world.query<Health>()
world.query2<Health, SceneTransform>()
world.query3<Health, SceneTransform, Target>()
world.query4<Health, SceneTransform, Target, EnemyAttack>()

// filters shape the match set without taking a slot
world.query<Health>(require: const [Enemy])            // must also carry Enemy
world.query<Health>(exclude: const [Stunned])          // skip carriers
world.query2<Health, Target>(
    require: const [Enemy], exclude: const [Stunned])  // combined
```

```dart
// cheatsheet: consuming queries
world.query2<Health, SceneTransform>()
    .each((entity, health, transform) { /* allocation-free; return=continue */ });
world.query<Health>()
    .eachUntil((entity, health) => health.current > 0);   // false stops the loop

for (final (entity, health) in world.query<Health>().records) {}
                                                  // for-loop form: allocates per row

final row = world.query<Health>(require: const [Player]).firstOrNull;
final (e, hp) = world.query<Health>(require: const [Player]).single;
                                                  // first/firstOrNull/single/
                                                  //   singleOrNull; rows as records
world.query<Health>().any((entity, h) => h.current < 10);        // predicate
world.query<Health>().firstWhere((entity, h) => h.current < 10); // row or null
world.query<Health>(require: const [Enemy]).isNotEmpty;          // existence
world.query<Health>().count();                                   // O(n) scan

world.single<Fighter>();       // THE one, unwrapped: component singletons
world.singleOrNull<Fighter>(); //   (throws on duplicates; null on none)

// already holding an Entity? skip the query; O(1) lookups:
world.get<Health>(enemy);      // throws if absent
world.tryGet<Health>(enemy);   // null if absent, despawned, or slot reused
world.has<Stunned>(enemy);
```

```dart
// queries stop at four type parameters: state that changes together
// belongs in one component (fewer components per query = fewer lookups);
// tags cost no slot; world.get covers one-off reads mid-loop. Split state
// out only when it is flipped independently (Stunned) or filtered on.
final class MotionState {
  final Vector3 velocity = Vector3.zero();
  bool grounded = false;
  double coyoteTimer = 0;
}
```

## Node lookups

`NodeRef` runs entity → node. `SceneNodeIndex` runs it back, for anything
that hands you a bare `Node`: `Scene.raycast`, a tap on the scene, a node
found by name, a parent walked to from a child mesh.

```dart
// Inserted by SceneGame.boot; always present.
final index = world.resource<SceneNodeIndex>();
```

```dart
// Walks up to the nearest bound ancestor, so a hit on a child mesh (an
// axe, a ragdoll limb) resolves to the entity that owns it.
final Entity? entity = index.entityOf(hitNode);   // null if nothing is bound
```

```dart
// Physics does not need it: the overlap helpers take the index and hand
// back entities, and EntityCollision arrives resolved (Physics).
world.physics.overlapSphereEntities(index, at, radius, (entity, hit) => true);
```

## Components, tags, bundles

```dart
final class Health {
  double current;
  final double max;
  Health(this.max) : current = max;
}

final class Player implements Tag { const Player(); }   // bit-cheap,
final class Enemy implements Tag { const Enemy(); }     //   filter-only
final class Stunned implements Tag { const Stunned(); }

List<Object> combatantBundle({required Node node, required double maxHealth}) =>
    [NodeRef(node), Health(maxHealth)];

List<Object> playerBundle(Node body) => [
  const Player(),                        // present for the whole lifetime
  ...combatantBundle(node: body, maxHealth: 100),
  Fighter(),                             // the state machine (see Machine)
];

List<Object> enemyBundle(Node node, {required Entity target}) => [
  const Enemy(),                         // composition = spread
  ...combatantBundle(node: node, maxHealth: 40),
  Target(target),                        // who to advance on (closeIn)
  EnemyAttack(),                         // the windup timer (see Time)
  const DespawnOnExit(GameStatus.playing),   // run-scoped (see States)
];
```

`Stunned` is the transient kind: flipped at runtime, entering and
leaving `exclude: [Stunned]` queries at the next frame boundary. Its full
loop is in Events: `applyDamage` adds it, `recoverFromStun` removes it.

```dart
// observe: a feature reacts to a component appearing or disappearing on
// any entity; explicit, per feature, at install time. onRemove gets the
// still-live instance (despawn strips components, so it fires there too)
game.observe<Stunned>(
  onAdd: (world, entity, stunned) => world.add(entity, StunStars()),
  onRemove: (world, entity, stunned) => world.remove<StunStars>(entity),
);

// removeAfter: the framework removes the component again on schedule,
// in fixed-step game time (pause and hitstop consume nothing); expiry fires
// onRemove like any other removal; re-adding refreshes the deadline
world.add(enemy, const Stunned(), removeAfter: 1.2);
world.expiryOf<Stunned>(enemy);          // seconds left, or null
```

```dart
final sword = world.spawn(
    [NodeRef(swordNode)],              // swordNode: yours
    ownedBy: player);                    // despawning the player despawns
                                         //   everything it owns
```

## Scheduling: sets and run conditions

```dart
abstract final class GameSets {
  static const movement = SystemSet('game.movement');
  static const combat = SystemSet('game.combat');
}

// main: order the phases once per schedule
game.configureSets(Schedules.fixedUpdate, [GameSets.movement, GameSets.combat]);
// features: join a phase; never import another feature's systems
game.addSystem(Schedules.fixedUpdate, closeIn, inSet: GameSets.movement);
// within a feature: order by function reference, so a rename is a compile error
game.addSystem(Schedules.fixedUpdate, enemyAttacks, after: [closeIn]);
// a pair the detector flags but the author knows is independent (disjoint
// entities, or different fields of one component): exempt exactly that
// pair: ordering untouched, every other pairing keeps the net
game.addSystem(Schedules.fixedUpdate, lockOn, writes: {Fighter},
    independentOf: [enemyAttacks]);
```

```dart
game.addSystem(Schedules.update, awardBounty,          // Events, below
    reads: const {},
    runIf: inState(GameStatus.playing).and(hasEvents<EnemyKilled>()));

game.addSystem(Schedules.fixedUpdate, spawnEnemyWave,  // yours: a system
    writes: {Enemy, Health, Target, EnemyAttack},      //   spawning enemyBundles
    // every() is schedule-aware (fixed delta here, frame delta in update);
    // periodicity lives at registration, never as a timer resource
    runIf: inState(GameStatus.playing).and(every(4.0)));

game.addSystem(Schedules.startup, spawnArenaDecor,     // yours: visual only
    reads: const {}, runIf: hasResource<Scene>());
    // gate on an optional capability: visual spawners skip on headless
    // boots, and the dependency sits in the manifest, not a guard

// cheatsheet: every built-in condition, and composition
runIf: inState(GameStatus.playing)          // state gate
runIf: every(2.5)                           // periodic (schedule-aware)
runIf: hasEvents<HitLanded>()               // only on frames carrying one
runIf: hasResource<Scene>()                 // optional capability present
runIf: inState(GameStatus.playing).and(every(2.5))
runIf: hasEvents<HitLanded>().or(hasEvents<EnemyKilled>())
runIf: not(inState(GameStatus.lost))

// a custom condition is any bool Function(World)
bool anyEnemiesLeft(World world) =>
    world.query<Health>(require: const [Enemy]).isNotEmpty;
```

## Custom schedules (game driven systems)

A schedule you dispatch. fire a systems on demand once. A game driven system, instead of a frame driven.
for example a turn, a round, a battle phase.
 `runSchedule` runs its systems once, in order. 

```dart
abstract final class BattleSchedules {
  static const turnStart = ScheduleLabel('battle.turnStart');
  static const resolveAction = ScheduleLabel('battle.resolveAction');
  static const turnEnd = ScheduleLabel('battle.turnEnd');
}

void installBattle(GameBuilder game) {
  game
    ..addSchedule(BattleSchedules.turnStart)       // declared at install;
    ..addSchedule(BattleSchedules.resolveAction)   //   no frame drives them
    ..addSchedule(BattleSchedules.turnEnd)
    // the same addSystem: ordering, sets, run conditions, access declarations
    ..addSystem(BattleSchedules.resolveAction, applyAttack, writes: {Health})
    ..addSystem(BattleSchedules.resolveAction, reportKills,
        reads: {Health}, after: [applyAttack])
    ..addSystem(BattleSchedules.turnEnd, tickStatusEffects,
        writes: {Poisoned}, runIf: inState(GameStatus.playing));
}
```

```dart
// dispatch from a system: the turn controller, itself a normal update system
void driveBattle(World world) {
  final queue = world.resource<TurnQueue>();
  if (!queue.actionReady) return;
  world.runSchedule(BattleSchedules.resolveAction);   // runs inline, to
  queue.advance();                                    //   completion
}

// or from outside the frame: a widget, a test, a network callback
GameScope.of(context).runSchedule(BattleSchedules.turnStart);
```

```dart
// cheatsheet: custom schedules
game.addSchedule(label)      // install time only
world.runSchedule(label)     // its systems, once, in compiled order
game.runSchedule(label)      // from a widget; TestGame.runSchedule in tests

// custom labels only; a built-in slot or OnEnter/OnExit throws
// settled on return: spawn, add, remove, despawn — so runs compose
// still frame-bound: setState, and mounting the nodes you spawned
// nesting runs inline; a schedule re-entering itself throws
// never inside a `.each`: the run ends in a flush
// world.dt = the last frame delta. Count turns with a counter
```

## Events

One-shot messages between systems. Sender and reader never reference
each other. Any class is an event; the channel opens on first emit.

```dart
final class EnemyKilled { final int bounty; EnemyKilled(this.bounty); }
```

```dart
// Emit. Nothing to register.
world.emit(EnemyKilled(10));                  // from a system
game.emit(const PauseRequested());            // from a widget
```

```dart
// System reads. Everything unread since this system last ran, in
// emission order; the cursor is per registration, so the function stays
// stateless and no system consumes another's events.
void awardBounty(World world) {
  for (final event in world.events<EnemyKilled>()) {
    world.resource<Score>().value += event.bounty;
  }
}

world.consumeAny<AttackPressed>();   // boolean form: any unread? true drains
                                     //   them. Same cursor as events()
                                     // both throw outside a running system
```

```dart
// Skip the system entirely on frames carrying none.
game.addSystem(Schedules.update, awardBounty,
    runIf: hasEvents<EnemyKilled>());

// Widget reads. Cleanup follows the widget's lifetime.
WorldEventListener<EnemyKilled>(
    onEvent: (context, event) => confetti(), child: const ScorePanel())
```

```dart
// Retention: the emitting frame plus seven update passes, so a
// fixed-step or briefly-gated reader keeps its edges on a high-refresh
// display. A reader lagging past the window skips the older events and a
// diagnostic reports it once.
game.configureEvent<AttackPressed>(retainedUpdates: null);
                             // null: keep until every reader consumed. What
                             //   an input edge crossing into a fixed step wants
```

## Input

Held state → `ButtonInput`. Analog → `AxisInput`. Buffered presses →
`InputBuffer`. Discrete intents → events. Widgets write, systems read.

```dart
enum PlayerAction { left, right, attack, roll }

enum GameAxis { moveX, moveY }

void installControls(GameBuilder game) {
  game
    ..world.insert(InputBuffer<PlayerAction>(window: 0.15))
    ..world.insert(AxisInput<GameAxis>());
}     // only to override a default: the accessors below create the resource
      //   on first use, so most games insert nothing
```

```dart
// Widget writes. Resolve once in a State, releaseAll() in dispose.
final buttons = GameScope.of(context).world.buttons<PlayerAction>();

buttons.setPressed(PlayerAction.attack, keyDown || touchDown);
                             // returns the edge crossed; OR-combine sources
                             //   so releasing one never releases the other
world.axes<GameAxis>().setValue(GameAxis.moveX, stick.dx);   // clamped [-1, 1]
world.buffer<PlayerAction>().record(PlayerAction.roll);
```

```dart
// System reads.
world.buttons<PlayerAction>().pressed(PlayerAction.attack);        // bool
world.buttons<PlayerAction>().axis(PlayerAction.left,
    PlayerAction.right);                                    // -1, 0, or +1
world.axes<GameAxis>().value(GameAxis.moveX);       // 0.0 if never written
world.buffer<PlayerAction>().consume(PlayerAction.roll);
                             // oldest unexpired match; the window expires on
                             //   wall time, so hitstop never eats an input
```

## Resources

One instance per world, keyed by type: the game's singletons (score,
wave number, settings). Any system reaches one without a query:

```dart
final class Score { int value = 0; }

game.world.insert(Score());              // once, in the owning feature
world.resource<Score>().value += 10;     // read/write from any system

WorldBuilder<int>(                       // reactive read in the UI:
    select: (w) => w.resource<Score>().value,   //   rebuilds on change
    builder: (context, score) => Text('$score'))
```

```dart
// owns teardown? implement Disposable; the framework calls dispose():
// game shutdown (reverse insertion order), a dropping reset, replacement.
final class Ambience implements Disposable {
  final ValueNotifier<double> volume = ValueNotifier(0.6);
  @override
  void dispose() => volume.dispose();
}
```

Framework state is promoted to members (`world.dt`, `world.clock`,
`world.buttons`, `world.physics`, `world.gizmos`), never `resource<T>()`.

## States

```dart
enum GameStatus { playing, lost }

game.addState<GameStatus>(GameStatus.playing);   // one machine per enum;
                                                 //   machines of different
                                                 //   enums are orthogonal
game.addSystem(Schedules.update, evaluateGameRules,
    reads: const {}, runIf: inState(GameStatus.playing));

void evaluateGameRules(World world) {
  final row = world.query<Health>(require: const [Player]).firstOrNull;
  if (row == null) return;
  final (_, health) = row;                       // destructure the record
  if (health.current <= 0) {
    world.setState(GameStatus.lost);   // applies at next frame start:
  }                                    //   OnExit(playing) → OnEnter(lost)
}

// the transition's other side (null before the first): an OnEnter system
// tells a resume from a fresh run without a hand-rolled flag
world.previousState<GameStatus>()
```

`enemyBundle` carries `DespawnOnExit(GameStatus.playing)`: leaving the
state despawns every enemy automatically; a run spawns freely and needs
no cleanup system.

## Time

```dart
// cheatsheet: the clock
world.dt            // schedule-aware: fixed delta in fixed schedules,
                    //   frame delta otherwise
world.delta / world.fixedDelta / world.unscaledDelta   // the explicit trio;
                                     //   unscaled = wall clock

world.clock.freezeFor(0.06);         // hitstop: 60ms of wall time
world.clock.timeScale = 0.5;         // slow motion: physics, animation,
world.clock.paused = true;           //   gameplay together; the fixed step
                                     //   never changes, so fixed-step
                                     //   gameplay stays deterministic
// HUD / camera shake keep moving on world.unscaledDelta
```

Durations live on components and tick with `world.dt`, so they pause,
slow and freeze with the game for free. The whole idiom is three lines:

```dart
final cooldown = GameTimer(0.8);                     // a field on a component
cooldown.tick(world.dt);                             // ticked by its system
if (fireHeld && cooldown.finished) { fire(); cooldown.reset(); }
```

In the game, the enemy's windup is one duration, so it is a `GameTimer`:

```dart
const enemyWindupSeconds = 0.9;
const enemyReach = 1.4;

final class EnemyAttack {
  final windup = GameTimer(enemyWindupSeconds);          // one-shot
}

void enemyAttacks(World world) {
  world.query3<EnemyAttack, Target, SceneTransform>(
      require: const [Enemy], exclude: const [Stunned])
      .each((entity, attack, target, transform) {
    attack.windup.tick(world.dt);
    if (!attack.windup.justFinished) return;   // true for exactly one tick
    attack.windup.reset();                     // re-arm in place

    final prey = world.tryGet<SceneTransform>(target.entity);
    if (prey == null) return;
    if ((prey.translation - transform.translation).length < enemyReach) {
      world.emit(HitLanded(target.entity, 15));    // applyDamage consumes it
    }
  });
}
```

```dart
// cheatsheet: the timer family (all tick with world.dt)
GameTimer(0.4)             // one-shot: finished / justFinished / reset()
GameTimer.repeating(1.5)   // completionsThisTick, can be >1 after a hitch
GameStopwatch()            // counts up: elapsed
DespawnAfter(2.0)          // component: timed despawn (muzzle flash, corpse)
Machine<S>(initial)        // modes; own section below
// system-level cadence → runIf: every(seconds), never a timer resource
```

## Machine

`GameTimer`'s sibling, for anything with modes. Lives on a component,
ticks with `world.dt`:

```dart
enum FighterPhase { idle, striking, rolling, staggered }

final phase = Machine<FighterPhase>(FighterPhase.idle);

phase.tick(world.dt);                // top of its system, every run
phase.state                          // the current mode
phase.elapsed                        // seconds in it, zeroed by go()
phase.go(FighterPhase.striking);     // transition
phase.justEntered(FighterPhase.striking)  // true from go() until the next
phase.justExited(FighterPhase.idle)       //   tick, so edges fire exactly once

// the state machine shape: switch on state, `when` guards the transition
switch (phase.state) {
  case FighterPhase.idle when attackPressed:                   // yours
    phase.go(FighterPhase.striking);
  case FighterPhase.striking when phase.elapsed >= 0.25:       // timed exit
    phase.go(FighterPhase.idle);
  default:
    break;
}
```

The fighter runs on one machine. Transitions come from input, time, or
events:

```dart
const strikeSeconds = 0.25, rollSeconds = 0.5, staggerSeconds = 0.4;
const iFrameStart = 0.05, iFrameEnd = 0.35;

final class Fighter {
  final phase = Machine<FighterPhase>(FighterPhase.idle);
  bool get iFramed => phase.state == FighterPhase.rolling &&
      phase.elapsed >= iFrameStart && phase.elapsed < iFrameEnd;
}

void fighterActions(World world) {
  final row = world.query<Fighter>(require: const [Player]).firstOrNull;
  if (row == null) return;
  final (entity, fighter) = row;
  final phase = fighter.phase..tick(world.dt);

  // event-driven: a hit interrupts anything except an i-framed roll
  for (final hit in world.events<HitLanded>()) {
    if (hit.target == entity && !fighter.iFramed) {
      phase.go(FighterPhase.staggered);
    }
  }

  switch (phase.state) {
    // input-driven; `when` guards the case
    case FighterPhase.idle
        when world.buffer<PlayerAction>().consume(PlayerAction.roll):
      phase.go(FighterPhase.rolling);
    case FighterPhase.idle when world.consumeAny<AttackPressed>():
      phase.go(FighterPhase.striking);

    // timed
    case FighterPhase.striking when phase.elapsed >= strikeSeconds:
      phase.go(FighterPhase.idle);
    case FighterPhase.rolling when phase.elapsed >= rollSeconds:
      phase.go(FighterPhase.idle);
    case FighterPhase.staggered when phase.elapsed >= staggerSeconds:
      phase.go(FighterPhase.idle);
    default:
      break;
  }

  // systems act on edges; a Machine never touches the world
  if (phase.justEntered(FighterPhase.staggered)) {
    world.buffer<PlayerAction>().clear();      // stale intents die with the hit
  }
}
```

```dart
// cheatsheet: consumeAny, the boolean shape of world.events
world.consumeAny<AttackPressed>();  // any since this system's last read?
                                    //   true consumes them; same
                                    //   per-registration cursor as events()
```

The strike itself resolves in Physics, below, gated on
`justEntered(striking)`.

## Physics

```dart
final game = await SceneGame.boot(
  physics: PhysicsWorld(                    // the generic world; the backend
    RapierWorld(gravity: Vector3(0, -9.81, 0)),   //   goes inside it
  ),
  features: [...],
);

const strikeRange = 1.6;

// the fighter's strike: a synchronous overlap the frame the machine
// enters `striking`; it emits the HitLanded that applyDamage (Events) consumes
void playerStrikes(World world) {
  final row = world.query2<Fighter, SceneTransform>(
      require: const [Player]).firstOrNull;
  if (row == null) return;
  final (_, fighter, transform) = row;
  if (!fighter.phase.justEntered(FighterPhase.striking)) return;

  world.physics.overlapSphereEntities(
      world.resource<SceneNodeIndex>(),      // node → entity (Node lookups)
      transform.translation, strikeRange,
      layerMask: Layers.enemy,               // your physics layer masks
      includeTriggers: false, (entity, hit) {
    world.emit(HitLanded(entity, 25));
    return true;                             // false stops early (hit caps)
  });
}
```

```dart
// contact events arrive resolved to entities, one frame late
// (flutter_scene's collision streams are async); use the synchronous
// overlap above when a hit must resolve NOW
void bumpOnContact(World world) {
  for (final collision in world.events<EntityCollision>()) {
    if (collision.source is! CollisionBegan) continue;
    // collision.a / collision.b are Entities; tryGet from here
  }
}

// immediate scene queries:
final down = Vector3(0, -1, 0);
final hit = world.physics.raycast(
    Ray(origin: playerFeet, direction: down),   // your backend's ray type
    maxDistance: 1.1);
```

## Debugging

### Entity debug

```dart
final grunt = world.spawn(
    [...enemyBundle(gruntNode, target: player), const Name('grunt-3')]);

print(world.debugDescribe(grunt));
// Entity(14 v2) "grunt-3" [Enemy, NodeRef, Health, Target, EnemyAttack,
//   DespawnOnExit, Name]     (one line; entries in store-registration order)

// a component that overrides toString renders its live value instead of
// its type; a Machine owner prints e.g. `striking (0.12s)`
```

### Gizmo debug

```dart
features: [installGizmos(enabled: kDebugMode), ...]   // opt-in render layer

void debugDrawCombat(World world) {
  world.query2<Fighter, SceneTransform>(require: const [Player])
      .each((entity, fighter, transform) {
    if (fighter.phase.state == FighterPhase.striking) {
      world.gizmos.sphere(transform.translation, strikeRange,
          color: GizmoColor.red);              // the hit volume, visible
    }
  });
}

world.gizmos.enabled = false;   // off = zero draw calls; calls stay in
                                //   shipping code as early-return no-ops
```

### Inspector

```dart
Stack(children: [
  SceneView(game.scene, onTick: game.onTick),
  InspectorOverlay(visible: showInspector),   // package: scene_dash_inspector
])                                            //   reads the world it is under
```

Live entities (filter by `Name`, tap for component values), resources,
system timings, event channels: read-only snapshots polled at 4 Hz,
zero cost hidden. Debug builds also warn once per system when a query
iterates inside another query's `each` (the accidental O(N×M) shape);
hoist the inner query (see the query rules above).

## Testing

The fighter's i-frames, frame-exact: `TestGame` runs the exact device
pipeline (schedule order, command boundaries, clock) with no scene, no
GPU:

```dart
final game = TestGame.headless(features: [installPlayer, installEnemies]);
final player = game.world.spawn([const Player(), Health(100), Fighter()]);

game.world.buffer<PlayerAction>().record(PlayerAction.roll);
game.pumpFixed(steps: 6);                    // 0.1s at 60Hz, inside the window
final (_, fighter) = game.world.query<Fighter>().single;
expect(fighter.iFramed, isTrue);

game.pumpFixed(steps: 18);                   // 0.4s: window closed, roll over
expect(fighter.phase.state, FighterPhase.idle);

// pump() = one rendered frame (accumulator-driven fixed steps);
// identical spawns + identical inputs ⇒ identical runs
```

## The rendering bridge

```dart
// the only bridge between world and scene; everything you see is a real Node
NodeRef(node)          // mounted into the scene automatically
SceneTransform.zero()    // when present, synced onto the bound node per frame
const PhysicsDriven()    // a physics body owns the transform instead
```

An entity's transform can also live on the node directly;
`NodeTransformOps` keeps per-frame mutation allocation-free:

```dart
const playerStrafeSpeed = 6.0;

void strafePlayer(World world) {
  final row = world.query<NodeRef>(require: const [Player]).firstOrNull;
  if (row == null) return;
  final (_, binding) = row;

  final strafe = world.buttons<PlayerAction>()
      .axis(PlayerAction.left, PlayerAction.right);
  final node = binding.node;
  final transform = node.localTransform;
  transform.storage[12] += strafe * playerStrafeSpeed * world.dt;
  node.localTransform = transform;   // reassignment marks the transform dirty
}
```
