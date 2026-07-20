# Scene-Dash v2

![Scene-Dash v2 — the combat sample](combat_sample_game.gif)

An entity-component-system runtime for
[`flutter_scene`](https://pub.dev/packages/flutter_scene).

Entities are generational ids. Components are plain Dart objects held in
sparse-set stores, dense arrays with O(1) insert, remove and lookup
and are mutated in place, so steady-state frames allocate nothing and
produce no GC pressure. Systems are plain functions scheduled on a fixed
timestep and per-frame phases; structural changes (spawn, despawn,
add/remove component) are command-buffered and applied at frame
boundaries, so they never invalidate a running query.

A `SceneNode` component binds an entity to a `flutter_scene` `Node`: the
framework mounts bound nodes into the scene and syncs `SceneTransform`
components onto them each frame. Rendering, cameras and physics remain
native `flutter_scene`; the framework never constructs or wraps
`SceneView`.

The core has no Flutter dependency, so gameplay runs headless under
`dart test`. A widget layer reads the world reactively: widgets select a
value and rebuild only when it changes.

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
```

When a feature spawned the entity (nothing in `main` holds the handle),
`.matching` resolves it through the world instead:

```dart
EntityBuilder<Health, double>.matching(
  require: const [Player],            // the first entity with Health + Player,
  select: (h) => h.current,           //   re-resolved each frame — a respawned
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

## A complete game in one file

```dart
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';
import 'package:vector_math/vector_math.dart' show Vector3;

Future<void> main() async {
  final game = await SceneGame.boot(features: [installCubes]);

  runApp(
    GameScope(                       // provides the game to the subtree
      game: game,
      child: MaterialApp(
        home: Scaffold(
          body: SceneView(           // flutter_scene widget; not wrapped
            game.scene,
            cameraBuilder: _camera,
            onTick: game.onTick,     // forwards frame ticks to the game
          ),
        ),
      ),
    ),
  );
}

Camera _camera(Duration elapsed) =>
    PerspectiveCamera(position: Vector3(0, 3, -6), target: Vector3.zero());

void installCubes(GameBuilder game) {          // a feature: a plain function
  game
    ..addSystem(Schedules.startup, spawnCube, writes: {Orbit, SceneTransform})
    ..addSystem(Schedules.update, orbitCubes, writes: {Orbit, SceneTransform});
}

void spawnCube(World world) => world.spawn(cubeBundle());

void orbitCubes(World world) {                 // a system: a plain function
  world.query2<Orbit, SceneTransform>().each((entity, orbit, transform) {
    orbit.phase += orbit.speed * world.dt;     // dt is schedule-aware
    transform
      ..x = orbit.radius * cos(orbit.phase)
      ..z = orbit.radius * sin(orbit.phase);
  });
}

final class Orbit {                            // a component: a plain class
  final double radius;
  final double speed;
  double phase;
  Orbit({required this.radius, required this.speed, this.phase = 0});
}

List<Object> cubeBundle() => [       // a bundle: a function → the spawn list
  Orbit(radius: 2, speed: 1),
  SceneTransform.zero(),
  SceneNode(Node(mesh: Mesh(CuboidGeometry(Vector3.all(0.8)), UnlitMaterial()))),
];
```

Hot reload applies edits to system bodies; there is no build step.

## Quick start

```bash
flutter channel master          # flutter_scene needs Flutter GPU
flutter pub get                 # resolve the workspace (repo root)
cd examples/scene_game
flutter run --enable-flutter-gpu
```

---

# Reference

The reference builds **one small game** across its sections: a fighter
who rolls through the swings of advancing enemies and strikes back.
Every section adds a piece; types defined in one section are reused in
the next. Blocks labeled `cheatsheet` list API and are not standalone
programs; `// yours` marks the rare identifier your game supplies.

## Application setup

```dart
final input = ButtonInput<PlayerAction>();     // the key handler writes it

final game = await SceneGame.boot(
  physics: RapierWorld(gravity: Vector3(0, -9.81, 0)),
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

runApp(GameScope(game: game, child: MyGameApp(game: game)));  // yours
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
    [SceneNode(node), Health(maxHealth)];

List<Object> playerBundle(Node body) => [
  const Player(),                        // present for the whole lifetime
  ...combatantBundle(node: body, maxHealth: 100),
  Fighter(),                             // the state machine (see Time)
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
    [SceneNode(swordNode)],              // swordNode: yours
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

## Events

Both ends of every loop: `applyDamage` consumes what the fighter's strike
emits (Physics, below) and produces what `awardBounty` and
`recoverFromStun` consume.

```dart
final class HitLanded {
  final Entity target;
  final double damage;
  HitLanded(this.target, this.damage);
}

final class EnemyKilled {
  final int bounty;
  EnemyKilled(this.bounty);
}

void applyDamage(World world) {
  // events since this system's last read, in emission order; the cursor
  // is per-registration, so the function stays stateless
  for (final hit in world.events<HitLanded>()) {
    final health = world.tryGet<Health>(hit.target);
    if (health == null) continue;
    health.current -= hit.damage;
    world.clock.freezeFor(0.06);               // hitstop (see Time)

    if (health.current <= 0) {
      world.emit(EnemyKilled(10));             // auto-registers on first use
      world.despawn(hit.target);
    } else if (world.has<Enemy>(hit.target)) {
      world.add(hit.target, const Stunned());  // closeIn skips them now
      world.add(hit.target, StunRecovery());
    }
  }
}

final class StunRecovery {
  final timer = GameTimer(0.8);
}

void recoverFromStun(World world) {
  world.query<StunRecovery>().each((entity, stun) {
    stun.timer.tick(world.dt);
    if (!stun.timer.justFinished) return;
    world.remove<Stunned>(entity);             // rejoins closeIn next boundary
    world.remove<StunRecovery>(entity);
  });
}

void awardBounty(World world) {
  for (final event in world.events<EnemyKilled>()) {
    world.resource<Score>().value += event.bounty;   // Score: see Resources
  }
}
```

Events are retained for the emitting frame plus one, so an every-frame
reader never misses one; a gated reader skips older events (reported once
by a diagnostic). `game.configureEvent<T>(retainedUpdates: null)` keeps
them until every reader consumed them, the right setting for input edges
that must survive to a fixed step. `world.events` throws outside a running system;
widgets use `WorldEventListener`.

## Input

Held state → a `ButtonInput` resource. Discrete intents → events.
Buffered presses → `InputBuffer`. The fighter's machine (Time, below)
consumes all three.

```dart
enum PlayerAction { left, right, attack, roll }

final class AttackPressed { const AttackPressed(); }

// in a widget: OR-combine sources so releasing one never releases the
// other; setPressed returns the edge it crossed
switch (input.setPressed(PlayerAction.attack, keyDown || touchDown)) {
  case ButtonEdge.pressed: game.emit(const AttackPressed());
  case ButtonEdge.released || ButtonEdge.none: break;
}

// held state, read directly in a system:
final strafe = world.buttons<PlayerAction>()
    .axis(PlayerAction.left, PlayerAction.right);        // -1, 0, or +1
```

```dart
// buffered: a roll pressed during a strike must fire the instant the
// strike ends; the fighter consumes it when its machine allows (Time)
if (edge == ButtonEdge.pressed) {
  world.buffer<PlayerAction>().record(PlayerAction.roll);   // widget side
}
// consume removes the oldest unexpired match; the press window (~150ms)
// expires on wall time, so hitstop never eats a buffered input
```

```dart
enum GameAxis { moveX, moveY }
// analog sticks: widget writes, system reads a plain double
axes.setValue(GameAxis.moveX, stick.dx);                 // clamped [-1, 1]
final x = world.axes<GameAxis>().value(GameAxis.moveX);  // 0.0 if never written
```

## Resources

```dart
final class Score { int value = 0; }

game.world.insert(Score());              // once, in the owning feature
world.resource<Score>().value += 10;     // read/write from any system

// owns teardown? implement Disposable; the framework calls dispose():
// game shutdown (reverse insertion order), a dropping reset, replacement.
final class ScoreCubit extends Cubit<int> implements Disposable {
  ScoreCubit() : super(0);
  @override
  void dispose() => close();             // blocs need nothing more
}
```

Framework state is promoted to members (`world.dt`, `world.clock`,
`world.buttons`, `world.physics`, `world.gizmos`), so `resource<T>()` is
only ever the game's own singletons.

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
```

`enemyBundle` carries `DespawnOnExit(GameStatus.playing)`: leaving the
state despawns every enemy automatically; a run spawns freely and needs
no cleanup system.

## Time

```dart
// cheatsheet: the clock
world.dt            // schedule-aware: fixed delta in fixed schedules,
                    //   frame delta otherwise
world.delta / world.fixedDelta       // the explicit pair

world.clock.freezeFor(0.06);         // hitstop: 60ms of wall time
world.clock.timeScale = 0.5;         // slow motion: physics, animation,
world.clock.paused = true;           //   gameplay together; the fixed step
                                     //   never changes, so fixed-step
                                     //   gameplay stays deterministic
// HUD / camera shake keep moving on FrameTime.unscaledDelta
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

The fighter has *modes*, so it is a `Machine`, `GameTimer`'s sibling:
`elapsed` is seconds in the current state (zeroed by `go`), and an edge
(`justEntered`/`justExited`) is true from `go()` until the machine's next
tick. Transitions can come from input, time, or events:

```dart
enum FighterPhase { idle, striking, rolling, staggered }

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
    // input-driven; `when` guards the case: it matches only while the
    // condition also holds
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
// cheatsheet: consumeAny — the boolean shape of world.events
world.consumeAny<AttackPressed>();  // any since this system's last read?
                                    //   true consumes them; same
                                    //   per-registration cursor as events()
```

The strike itself resolves in Physics, below, gated on
`justEntered(striking)`.

```dart
// cheatsheet: the timer family (all tick with world.dt)
GameTimer(0.4)             // one-shot: finished / justFinished / reset()
GameTimer.repeating(1.5)   // completionsThisTick, can be >1 after a hitch
GameStopwatch()            // counts up: elapsed
DespawnAfter(2.0)          // component: timed despawn (muzzle flash, corpse)
Machine<S>(initial)        // modes: state / elapsed / go / justEntered / justExited
// system-level cadence → runIf: every(seconds), never a timer resource
```

## Physics

```dart
final game = await SceneGame.boot(
  physics: RapierWorld(gravity: Vector3(0, -9.81, 0)),   // any native
  features: [...],                                       //   flutter_scene world
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
      world.resource<SceneNodeIndex>(),      // resolves hit nodes → entities
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
// Entity(14 v2) "grunt-3" [Enemy, SceneNode, Health, Target, EnemyAttack,
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
  GameView(game: game),
  InspectorOverlay(visible: showInspector),   // package: scene_dash_inspector
])
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
SceneNode(node)          // mounted into the scene automatically
SceneTransform.zero()    // when present, synced onto the bound node per frame
const PhysicsDriven()    // a physics body owns the transform instead
// SceneNodeIndex maps a hit node back to its entity (playerStrikes, above)
```

An entity's transform can also live on the node directly;
`NodeTransformOps` keeps per-frame mutation allocation-free:

```dart
const playerStrafeSpeed = 6.0;

void strafePlayer(World world) {
  final row = world.query<SceneNode>(require: const [Player]).firstOrNull;
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

## Packages and examples

| Path | Purpose |
| --- | --- |
| [`packages/scene_dash_v2_core`](packages/scene_dash_v2_core) | Pure-Dart ECS runtime, authoring surface, headless `TestGame`. |
| [`packages/scene_dash_v2`](packages/scene_dash_v2) | `flutter_scene` integration: `SceneGame.boot`, mounting, transform sync, physics bridge, gizmos, widget layer. Re-exports core, so one import covers both. |
| [`examples/scene_game`](examples/scene_game) | Complete game: Rapier physics, one feature per folder. |
| [`examples/headless_example`](examples/headless_example) | The core without Flutter. |
| [`examples/scene_benchmark`](examples/scene_benchmark) | On-device render benchmark: static vs mount-only vs ECS vs instanced. |
| [`examples/combat_sample`](examples/combat_sample) | Combat slice: KayKit knight against waves of barbarians lock-on, buyable skills, giants, Rapier ragdolls, authored `.fmat` materials. Gameplay pinned headless. |
| [`benchmarks`](benchmarks) | Query, structural, and record-overhead benchmarks. |

```text
examples/scene_game/lib/
├── player/          # each folder: one feature
├── projectiles/     #   (components, bundles, systems, resources)
├── rocks/
├── collectables/
├── rules/
├── world/
├── decor/
├── hud/
└── main.dart
```

Deeper docs: [architecture](docs/concept.md) ·
[integration](docs/integration.md) 

## Development

```bash
flutter pub get                                   # workspace, from the root

cd packages/scene_dash_v2_core && dart test       # engine + surface
cd packages/scene_dash_v2 && flutter test         # integration + widgets
cd examples/scene_game && flutter test            # the game's headless suites
dart analyze                                      # clean, always
```