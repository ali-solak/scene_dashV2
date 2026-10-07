# Reference

Every public API, grouped by what you use it for.

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
  - [Custom schedules](#custom-schedules-game-driven-systems)
  - [Time](#time)
  - [GameTween](#gametween)
    - [With Routine](#with-routine)
  - [Smoothing](#smoothing)
- Coordination
  - [Observers](#observers)
  - [Events](#events)
  - [Input](#input)
  - [States](#states)
  - [Machine](#machine)
  - [Routine](#routine)
    - [Machine or Routine](#machine-or-routine)
    - [The contract](#the-contract)
- flutter_scene
  - [Physics](#physics)
  - [The rendering bridge](#the-rendering-bridge)
  - [Scene components](#scene-components)
- Tooling
  - [Debugging](#debugging)
    - [Entity debug](#entity-debug)
  - [Testing](#testing)

## World-reactive widgets

These widgets read one value from the world every frame. They rebuild only
when that value changes. A parent rebuild can also run the builder.

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

The other builders work the same way: pick a value, rebuild when it
changes.

```dart
WorldBuilder<int>(select: (w) => w.query<Health>().having<Enemy>().count(),
    builder: (ctx, n) => Text('$n enemies'))       // any world-derived value

GameStateBuilder<GameStatus>(builder: (ctx, s) => switch (s) { ... })
                                                   // a subtree per game state

WorldEventListener<EnemyKilled>(onEvent: (ctx, e) => shakeScore(ctx),
    child: const ScorePanel())                     // world events into UI;
                                                   //   widget-lifetime cleanup

WorldBuilder<double>.pulse(                       // short-lived feedback
    select: (w) => playerHp(w),
    trigger: (previous, next) => next < previous,  // the frame HP drops,
    duration: 0.4,                                 //   pulse runs 1 → 0 on
    pulseBuilder: (ctx, pulse, child) =>           //   wall time, then rests
        HurtVignette(intensity: pulse * pulse))    //   at 0; pause never
                                                   //   freezes it
                                     // trigger on the OUTCOME (the value
                                     //   moved), not the event: events also
                                     //   fire for blocked/i-framed hits

WorldBuilder<int>(select: countAmmo, builder: ..., every: Duration(seconds: 1))
                                     // escape hatch: a heavy select polls on a
                                     //   wall-clock interval, not every frame
```

If a feature spawned the entity and you have no handle to it, `.matching`
finds it by its components:

```dart
EntityBuilder<Health, double>.matching(
  where: (q) => q.having<Player>(),   // an entity with Health + Player, kept
  select: (h) => h.current,           //   while it matches; a respawned
  builder: (context, hp) =>           //   player is picked up automatically
      HealthBar(hp),
  absent: const RespawnCountdown(),   // no match, dead, or Health gone
)
// resolving by one component while watching another stays the composition:
// WorldBuilder<Entity?> (resolve) wrapping EntityBuilder (watch)
```

- `select`: return the value to show, like `health.current`. The widget
  rebuilds when it changes (`==`). Lists, sets, maps and iterables compare
  by contents, one level deep, so you can return a live list without
  copying it.
- `every`: how often to check. Leave it out to check every frame.

For a widget *inside* the 3D world, like a health bar over an enemy, put a
`flutter_scene` `WidgetComponent` on a child node. The scene graph places
it, projects it, and hides it behind geometry.

Widgets never change components. To change the game from the UI, write to
`ButtonInput` or call `game.emit`.

### GameScope

`GameScope` is one `InheritedWidget` at the top of the tree. Any widget
below it reaches the game through its own `context`, so you never pass the
game through constructors:

```dart
runApp(GameScope(game: game, child: const MyGameApp()));

class PauseButton extends StatelessWidget {                 // const: nothing
  const PauseButton({super.key});                           //   passed in

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: () => GameScope.of(context).emit(const PauseRequested()),
    child: Text('score ${context.world.resource<Score>().value}'),
  );                             // context.world / context.game: shortcuts
}                                //   for one-off reads; not reactive, use
                                 //   the builders above for that
```

`GameScope.of(context)` is the whole API. `GameHost` is the same widget
with hot-reload support.

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
  ],
);

runApp(GameHost(game: game, child: const MyGameApp()));   // yours; the
                            // subtree reaches `game` through GameScope.of
```

## Features and systems

A feature is a function that registers systems. A system is a
`void Function(World)` that keeps no state of its own.

```dart
const enemyCloseSpeed = 1.5;

void installEnemies(GameBuilder game) {
  game
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
  world.query2<SceneTransform, Target>().having<Enemy>().without<Stunned>()   // stunned: frozen
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

Spawn, despawn, add and remove are queued and applied at the frame
boundary, so they never break a query that is still running.

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
```

```dart
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

`Stunned` is a tag you add and remove at runtime. The entity drops out of
`.without<Stunned>()` queries, and comes back, at the next frame boundary.
`applyDamage` (Events) adds it with `removeAfter`, which takes it off again.

A bundle binds to a plain `flutter_scene` node, usually built by the system
that spawns the entity. Systems cannot `await`, so load models with
`loadScene` up front and pass them in through a resource (Resources).

```dart
void spawnPlayer(World world) {
  final body = Node(
    mesh: Mesh(
      CapsuleGeometry(radius: 0.3, height: 1.2),
      PhysicallyBasedMaterial(),
    ),
  );
  world.spawn(playerBundle(body));   // NodeRef mounts it into the scene
}
```

```dart
final sword = world.spawn(
    [NodeRef(swordNode)],              // swordNode: yours
    ownedBy: player);                    // despawning the player despawns
                                         //   everything it owns
```

```dart
// cheatsheet: stores create themselves, nothing to register
world.spawn([const Enemy(), Health(40)]);   // first spawn of a tag or
                                            //   component creates its store
world.add(enemy, const Mired());            // so does add<T>
world.query<Health>().having<Mired>();      // and any type argument:
world.tryGet<Brawler>(entity);              //   queries, filters, lookups

// subtypes live in their supertype's store once one exists
world.spawn([Goblin()]);                    // Goblin extends Unit, queried
world.query<Unit>();                        //   as Unit: Goblin rows show up
world.tryGet<Goblin>(entity);               // reads it back from Unit's store
world.query<Goblin>();                      // gives Goblin its own store: later
                                            //   spawns land there, not in Unit
```

## Queries

Use `.each` in per-frame loops. It allocates nothing. Inside it, `return`
skips to the next row; use `eachUntil` to stop early.

`snapshot()` builds a list of records right away, so the matching entities
are fixed at the moment you call it. It does not copy the components: their
fields can still change, and they can outlive an entity that gets despawned.

`.having<T>()` and `.without<T>()` filter which entities match. If you stored an
`Entity` on a component, like `Target.entity`, get it back with `tryGet`.
It returns `null` once that entity is gone. `closeIn` above uses all of
this.

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

// filters shape the match set without taking a slot; chain as many as needed
world.query<Health>().having<Enemy>()            // must also carry Enemy
world.query<Health>().without<Stunned>()          // skip carriers
world.query2<Health, Target>().having<Enemy>().without<Stunned>()  // combined

// entity-only rows, for tags: no component slot to fill
world.entitiesWith<Enemy>().without<Stunned>().each(world.despawn);
world.entitiesWith<Player>().firstOrNull;
```

```dart
// cheatsheet: consuming queries
world.query2<Health, SceneTransform>()
    .each((entity, health, transform) { /* allocation-free; return=continue */ });
world.query<Health>()
    .eachUntil((entity, health) => health.current > 0);   // false stops the loop

for (final (entity, health) in world.query<Health>().snapshot()) {}
                                                  // for-loop form: allocates a
                                                  //   list

final row = world.query<Health>().having<Player>().firstOrNull;
final (e, hp) = world.query<Health>().having<Player>().single;
                                                  // first/firstOrNull/single/
                                                  //   singleOrNull; rows as records
world.query<Health>().any((entity, h) => h.current < 10);        // predicate
world.query<Health>().firstWhere((entity, h) => h.current < 10); // row or null
world.query<Health>().having<Enemy>().isNotEmpty;          // existence
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

`NodeRef` goes from entity to node. `SceneNodeIndex` goes back from node to
entity. Use it whenever something hands you a bare `Node`: `Scene.raycast`,
a tap on the scene, a node found by name, or a parent reached from a child
mesh.

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

## Resources

A resource is one shared object that any system can fetch by type: score,
settings, the wave number, an audio bus, a shared pool. Each world holds
one instance per type, and no query is needed:

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

Built-in framework state lives directly on `world` (`world.dt`,
`world.clock`, `world.buttons`, `world.physics`), never behind
`resource<T>()`.

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
    world.query<Health>().having<Enemy>().isNotEmpty;
```

## Custom schedules (game driven systems)

A custom schedule runs only when you tell it to, not every frame. Use it
for a turn, a round, or a battle phase. `runSchedule` runs its systems
once, in order.

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

Durations belong on components and tick with `world.dt`, so they pause,
slow down and freeze along with the game:

```dart
final cooldown = GameTimer(0.8);                     // a field on a component
cooldown.tick(world.dt);                             // ticked by its system
if (fireHeld && cooldown.finished) { fire(); cooldown.reset(); }
```

The enemy's windup is a single duration, so it is a `GameTimer`:

```dart
const enemyWindupSeconds = 0.9;
const enemyReach = 1.4;

final class EnemyAttack {
  final windup = GameTimer(enemyWindupSeconds);          // one-shot
}

void enemyAttacks(World world) {
  world.query3<EnemyAttack, Target, SceneTransform>().having<Enemy>().without<Stunned>()
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
GameTween.number(0, 1, .4) // a value over a duration; own section below
smoothTo(v, target, dt, h) // chasing a moving target; own section below
Machine<S>(initial)        // modes; own section below
// system-level cadence → runIf: every(seconds), never a timer resource
```

## GameTween

Moves a value over game time. It ticks with `world.dt`, so it pauses and
slows down with the game.

```dart
final fade = GameTween.number(1, 0, 0.8, curve: Curves.easeIn);
```

```dart
fade.tick(world.dt);
material.baseColorFactor.a = fade.value;

if (fade.justFinished) world.despawn(entity);
```

It also works for vectors and colors:

```dart
final move = vector3Tween(from, to, 1.2);
final tint = colorTween(white, red, 0.4);
```

It can change direction without jumping:

```dart
tween.reverse();          // back the way you came, from where you are
tween.retarget(newEnd);   // pick a new end, keep the duration
```

```dart
tween.value
tween.fraction
tween.eased
tween.finished
tween.justFinished

tween.reset();
tween.reverse();
tween.retarget(to);
```

Use Flutter's `Curves` for easing.

### With Routine

`Routine` decides the order, `GameTween` does the movement. Here a door
opens, waits for the player to pass, then swings shut:

```dart
const doorSequence = Sequence([
  OpenDoor(),
  UntilPlayerPassed(),
  CloseDoor(),
]);
```

```dart
final class Door {
  Door(this.node);
  final Node node;
  final routine = Routine(doorSequence);
  final angle = GameTween.number(0, math.pi / 2, 0.6,
      curve: Curves.easeInOut);
}
```

```dart
door.routine.advance(world.dt, (step) {
  switch (step) {
    case OpenDoor():
      return swing(door, world.dt);

    case UntilPlayerPassed():
      return playerPassed(world) ? StepResult.success : StepResult.running;

    case CloseDoor():
      if (!door.angle.reversed) door.angle.reverse();
      return swing(door, world.dt);
  }
});

StepResult swing(Door door, double dt) {
  door.angle.tick(dt);
  door.node.localTransform = Matrix4.rotationY(door.angle.value);
  return door.angle.finished ? StepResult.success : StepResult.running;
}
```

One tween drives both halves. On the way back, `reverse()` flips it. The
`reversed` check makes it flip once, not on every tick.

`GameTween` has no chaining. To run several animations in order, use
`Routine`.

## Smoothing

When the target keeps moving, smooth toward it instead of using a tween:

```dart
rig.position.smoothToward(playerPosition, world.dt, 0.08);
```

```dart
smoothTo(value, target, dt, halfLife)
position.smoothToward(target, dt, halfLife)
smoothBlend(dt, halfLife)
moveToward(value, target, amount)
```

`halfLife` is the time it takes to cover half of the remaining distance.

```dart
GameTween   // fixed start to end over a duration
smoothTo    // follow a changing target
moveToward  // move at a fixed rate until you arrive
```

## Observers

Observers run when a component is added to, or removed from, any entity.
Register them in a feature at install time. `onRemove` still receives the
component, and it also runs when an entity is despawned.

```dart
game.observe<Stunned>(
  onAdd: (world, entity, stunned) => world.add(entity, StunStars()),
  onRemove: (world, entity, stunned) => world.remove<StunStars>(entity),
);

// removeAfter removes the component again on schedule, in fixed-step game
// time. Expiry fires onRemove like any other removal; re-adding refreshes it.
world.add(enemy, const Stunned(), removeAfter: 1.2);
world.expiryOf<Stunned>(enemy);          // seconds left, or null
```

## Events

Events are one-time messages between systems. The sender and the reader
never know about each other. Any class can be an event, and its channel
opens the first time you emit one.

```dart
final class EnemyKilled { final int bounty; EnemyKilled(this.bounty); }
```

```dart
// Emit. Nothing to register.
world.emit(EnemyKilled(10));                  // from a system
game.emit(const PauseRequested());            // from a widget
```

```dart
// One channel per event: its own class when that channel exists (a reader or
// configureEvent registered it), otherwise the type it is emitted as.
world.emit(EnemyKilled(10));                  // events<EnemyKilled>()
game.emit(lost ? Defeat() : Victory());       // inferred as GameEvent, still
                                              //   reaches events<Victory>()
world.emit<GameEvent>(EnemyKilled(10));       // no EnemyKilled channel yet:
                                              //   events<GameEvent>() gets it
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

world.consumeAny<AttackPressed>();   // boolean form: advances the cursor in
                                     //   constant time without a result list
                                     // same cursor as events()
                                     // both throw outside a running system
```

```dart
// The damage loop the other sections point at: enemyAttacks and
// playerStrikes emit HitLanded, applyDamage spends it.
final class HitLanded {
  final Entity target;
  final double damage;
  const HitLanded(this.target, this.damage);
}

void applyDamage(World world) {
  for (final hit in world.events<HitLanded>()) {
    if (world.tryGet<Fighter>(hit.target)?.iFramed ?? false) continue;
    final health = world.tryGet<Health>(hit.target);
    if (health == null) continue;
    health.current -= hit.damage;
    world.add(hit.target, const Stunned(), removeAfter: 0.5);   // re-adding
                                                                //   refreshes
    if (health.current <= 0 && world.has<Enemy>(hit.target)) {
      world.emit(EnemyKilled(10));                // awardBounty reads it
      world.despawn(hit.target);
    }
  }
}
```

The framework releases system readers at shutdown and widget readers on
unmount. If you create an `EventReader` yourself through the advanced API,
call `dispose()` when you are done. A disposed reader stops holding events
and stops taking part in channel cleanup. Reading from it afterwards throws
`StateError`.

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

Pick by shape. Buttons held down → `ButtonInput`. Analog sticks →
`AxisInput`. Presses that should wait a moment to be used → `InputBuffer`.
One-off intents → events. Widgets write input, systems read it.

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

## States

```dart
enum GameStatus { playing, lost }

game.addState<GameStatus>(GameStatus.playing);   // one machine per enum;
                                                 //   machines of different
                                                 //   enums are orthogonal
game.addSystem(Schedules.update, evaluateGameRules,
    reads: const {}, runIf: inState(GameStatus.playing));

void evaluateGameRules(World world) {
  final row = world.query<Health>().having<Player>().firstOrNull;
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

`enemyBundle` carries `DespawnOnExit(GameStatus.playing)`, so every enemy
is despawned when the game leaves `playing`. A run can spawn freely without
a cleanup system.

## Machine

Like `GameTimer`, but for anything with modes. It lives on a component and
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

The fighter runs on one machine. Its transitions come from input, time, or
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
  final row = world.query<Fighter>().having<Player>().firstOrNull;
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

The strike itself happens in Physics, below, triggered by
`justEntered(striking)`.

## Routine

`Routine` runs gameplay steps in a fixed order: wave directors, objectives,
encounters, tutorials.

The plan is a `const` value, so one plan can drive every entity that runs
it.

The steps are your own types:

```dart
sealed class WaveStep extends Step<WaveStep> {
  const WaveStep();
}

final class Spawn extends WaveStep {
  const Spawn(this.count);
  final int count;
}

final class Clear extends WaveStep {
  const Clear();
}

final class Rest extends WaveStep {
  const Rest(this.seconds);
  final double seconds;
}
```

Build them into a plan:

```dart
const endless = Repeat(Sequence([Spawn(5), Clear(), Rest(3)]));
```

Each thing running that plan gets its own routine:

```dart
final class WaveDirector {
  final routine = Routine(endless);
}
```

Then one system says what the steps do:

```dart
void runWaves(World world) {
  final routine = world.resource<WaveDirector>().routine;

  routine.advance(world.dt, (step) => switch (step) {
    Spawn(:final count) => spawnEnemies(world, count),

    Clear() => enemiesLeft(world) == 0
        ? StepResult.success
        : StepResult.running,

    Rest(:final seconds) => routine.elapsed >= seconds
        ? StepResult.success
        : StepResult.running,
  });
}
```

A step can act at once or wait for your game to catch up. `Spawn` is done
the moment it fires. `Clear` stays running until the field is empty.

### Machine or Routine

Both decide what comes next. The difference is where the order lives:

```dart
Machine   // states you switch between, any order, decided as you go
Routine   // steps you go through, in an order written down up front
```

Patrolling, chasing, reloading and being staggered form a behaviour loop;
use `Machine`. Use `Routine` when the order itself is the game flow:

```dart
const encounter = Sequence([
  StartEncounter(),
  UntilEnemiesDefeated(),
  OpenExit(),
]);

const advance = Sequence([
  MoveTo(ridge),
  UntilInPosition(),
  Attack(leftFlank),
]);
```

### The contract

```dart
// cheatsheet: what a step returns
StepResult.running   // stay on this step
StepResult.success   // move on
StepResult.failure   // this path failed
```

```dart
// cheatsheet: the three building blocks
Sequence([a, b, c])   // run in order. stops if one fails
Select([a, b, c])     // use the first one that succeeds
Repeat(a, times: 3)   // repeat. null means forever
```

Steps that finish right away do not each cost a frame.

```dart
// cheatsheet: reading and saving a routine
routine.current       // the step being worked on, null once done
routine.elapsed       // seconds on it, zeroed when it moves on
routine.finished      // reached the end, or gave up
routine.failed        // gave up
routine.restart();    // back to step one

routine.path          // save these three, restore with
routine.loops         //   Routine.resume(plan, path:, loops:, elapsed:)
routine.elapsed
```

Add a new step type and the compiler shows you the one place to handle it.

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
  final row =
      world.query2<Fighter, SceneTransform>().having<Player>().firstOrNull;
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

## The rendering bridge

```dart
// the only bridge between world and scene; everything you see is a real Node
NodeRef(node)            // mounted into the scene automatically
SceneTransform.zero()    // when present, written to the bound node whenever
                         //   it changes (or the node's matrix is replaced)
const PhysicsDriven()    // a physics body owns the transform instead
```

An entity's transform can also live on the node itself.
`NodeTransformOps` changes it every frame without allocating:

```dart
const playerStrafeSpeed = 6.0;

void strafePlayer(World world) {
  final row = world.query<NodeRef>().having<Player>().firstOrNull;
  if (row == null) return;
  final (_, binding) = row;

  final strafe = world.buttons<PlayerAction>()
      .axis(PlayerAction.left, PlayerAction.right);
  binding.node.mutateLocalTransform(   // edits in place and marks it dirty
    (m) => m.storage[12] += strafe * playerStrafeSpeed * world.dt,
  );
}
```

## Scene components

`flutter_scene` attaches authored components to nodes when an `.fscene`
file loads. They are not ECS components: no entity is spawned for them and
no query finds them. If gameplay owns them, bake them into entities. If you
only need the authored values, read them from the scene tree.

```dart
// The authored side: a flutter_scene Component, annotated so
// flutter_scene_codegen writes its .fscene codec. Fields are mutable and
// carry their defaults; the class needs no constructor.
@SceneComponent('game.torch')
class Torch extends Component {
  @NumberProperty(min: 0)
  double radius = 1;

  @BoolProperty()
  bool enabled = true;
}
```

Baking spawns one entity for each authored node:

```dart
features: [
  installSceneBaker<Torch>(),   // one entity per node: [torch, NodeRef(node)]
]
```

```dart
// Which is the point: authored markers are now ordinary entities, and
// NodeRef gets back to the node each came from.
world.query2<Torch, NodeRef>().each((entity, torch, ref) {
  ref.node.visible = torch.enabled;
});
```

`bundle` sets what each entity carries, so you can add your own
components:

```dart
installSceneBaker<SpawnPoint>(
  bundle: (node, spawn) => [
    spawn,                            // the authored data, as loaded
    NodeRef(node),
    Patrol(radius: spawn.radius),     // your component, free to change
  ],
)
```

`spawn` is the same object the node holds, so writing to it also changes
the node's copy. Keep anything that changes in your own component.

```dart
// The baker runs once at startup, seeing only nodes parented by then: queued
// SceneCommands have not flushed yet, and it says so in debug when it finds
// nothing. Loading is async, so a level mounted later is baked from your
// loading code, not from a system. Nodes already baked are skipped, and
// `root:` scopes the walk to the level just added.
final levelRoot = await loadScene('assets/level2.fscene');
scene.add(levelRoot);
world.bakeSceneComponents<Torch>(root: levelRoot);
```

If you do not want an entity at all, such as a marker you only draw or a
one-time pass at load, read the scene graph directly:

```dart
// Lazy, so breaking out of the loop stops the walk.
for (final (node, torch) in world.sceneComponents<Torch>()) {
  lightUp(node.globalTransform.getTranslation(), torch.radius);   // yours
}
```

Both take `root:` to limit them to one level instead of everything
loaded. Systems cannot `await loadScene`, so if systems need to scope to a
level, keep the node it returned in a resource (Resources).

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

Debug builds warn once per system when a query loops inside another
query's `each`. That can cause quadratic work, so move the inner query out
of the loop.

## Testing

This test checks the fighter's i-frames down to the exact frame. `TestGame`
runs the real device pipeline (schedule order, command boundaries, clock)
with no scene and no GPU:

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

