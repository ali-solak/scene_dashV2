# Scene-Dash v2

An entity-component-system runtime for
[`flutter_scene`](https://pub.dev/packages/flutter_scene).

Entities are generational ids. Components are plain Dart objects held in
sparse-set stores. dense arrays with O(1) insert, remove and lookup.
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

The core has no Flutter dependency — gameplay runs headless under
`dart test`. A widget layer reads the world reactively: widgets select a
value and rebuild only when it changes.

## World-reactive widgets

Widgets select a value from the world and rebuild only when it changes;
`WorldOverlay` places widgets at entities' projected 3D positions.

```dart
// rebuilds only when the selected value changes
EntityBuilder<Health, double>(
  entity: player,
  select: (h) => h.current,
  builder: (context, hp) => HealthBar(hp),
  absent: const RespawnCountdown(),          // entity dead / component gone
)

// widgets at entities' projected 3D positions, one per query match
WorldOverlay(
  camera: rigCamera,                         // same camera you give SceneView
  children: [
    WorldAnchors<EnemyTag>(offsetY: 2.2,
        builder: (ctx, enemy) => EnemyHealthBar(enemy)),
  ],
)

// selects a subtree per state-machine value
GameStateBuilder<GameStatus>(
  builder: (context, s) => switch (s) {
    GameStatus.playing => const BattleHud(),
    GameStatus.lost    => const GameOverPanel(),
  },
)

// world events delivered to UI; subscription tied to widget lifetime
WorldEventListener<BossDefeated>(
  onEvent: (context, event) => confetti.play(),
  child: const SizedBox(),
)

// any world-derived value: query counts, resources, aggregates
WorldBuilder<int>(
  select: (world) => world.query<Rock>().count(),
  builder: (context, rocks) => Text('$rocks rocks'),
)
```

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

List<Object> cubeBundle() => [                 // a bundle: a function returning the spawn list
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

## Application setup

```dart
// objects shared with the widget shell; gameplay state is constructed
// inside its owning feature and read back through the world
final input = ButtonInput<GameAction>();       // the key handler writes it
final cameraRig = CameraRig();                 // the camera builder reads it

final game = await SceneGame.boot(
  physics: RapierWorld(gravity: Vector3(0, -gravityStrength, 0)),
  features: [
    (game) {
      game
        ..addState<GameStatus>(GameStatus.playing)   // whole-game mode machine
        ..configureSets(Schedules.update,            // cross-feature phase
            [GameSets.logic, GameSets.rules])        //   order, declared once
        ..world.insert(input)                        // world singletons
        ..world.insert(cameraRig);
    },
    installWorldGeometry,
    installPlayer,
    installProjectiles,                        // owns and inserts its Blaster
    installRules,
    installGizmos(enabled: kDebugMode),        // parameterized feature:
  ],                                           //   a function returning one
);

runApp(GameScope(game: game, child: MyGameApp(game: game, input: input)));
```

## Features and systems

```dart
void installPlayer(GameBuilder game) {
  game.world.insert(PlayerKnockback());
  game
    ..registerTag<Player>()
    ..addSystem(Schedules.startup, spawnPlayer,      // once, at boot
        writes: {Player, SceneNode, PlayerVisuals})
    ..addSystem(OnEnter(GameStatus.playing), resetPlayerOnRunStart,
        writes: {SceneNode, PlayerVisuals})          // on every run (re)start
    ..addSystem(Schedules.fixedUpdate, movePlayer,
        writes: {SceneNode},                 // access declaration for the
                                             //   conflict detector
        inSet: GameSets.movement,          // ordered against other features
        runIf: inState(GameStatus.playing));         // skipped while not playing
}

// systems are stateless functions; every accessed type appears in a
// query signature or on a world call
void movePlayer(World world) {
  final player = world.query<SceneNode>(require: const [Player]).firstOrNull;
  if (player == null) return;

  final node = player.$2.node;
  final input = world.buttons<GameAction>();
  final strafe = input.axis(GameAction.left, GameAction.right); // -1, 0, +1
  final transform = node.localTransform;
  transform.storage[12] += strafe * playerStrafeSpeed * world.dt;
  node.localTransform = transform;         // reassignment marks the transform dirty
}
```

Schedule slots: `startup`/`shutdown` once; `frameStart`, `fixedUpdate`,
`update`, `renderSync` every frame; `OnEnter`/`OnExit` on transitions.
Spawn/despawn/add/remove are deferred to the frame boundary — structural
changes never break a running query.

## Queries

```dart
void applyVelocity(World world) {
  world.query2<SceneTransform, Velocity>(exclude: const [Stunned])
      .each((entity, transform, velocity) {          // allocation-free;
    transform                                        //   `return` = continue,
      ..x += velocity.x * world.dt                   //   eachUntil = break
      ..z += velocity.z * world.dt;
  });
}
```

```dart
world.query<Health>(require: const [Enemy])   // must also carry Enemy
world.query2<A, B>(exclude: const [Stunned])  // skip entities carrying it

q.isEmpty / q.isNotEmpty                      // existence
q.any((e, a) => ...) / q.firstWhere((e, a) => ...)   // predicates; row or null
q.first / q.firstOrNull / q.single / q.singleOrNull  // rows as records
q.count()                                     // O(n) scan

for (final (e, a, b) in world.query2<A, B>().records) {}   // for-loop form:
                                              //   allocates a record per row
```

```dart
// lookup by a held Entity is O(1); Entity is a value type — storable on
// components, carried in events
final class Homing {
  final Entity target;
  Homing(this.target);
}

void homeMissiles(World world) {
  world.query2<Homing, SceneTransform>().each((missile, homing, transform) {
    final target = world.tryGet<SceneTransform>(homing.target);
    if (target == null) return;        // null if despawned or slot reused
    final step = missileSpeed * world.dt;
    final dir = (target.translation - transform.translation).normalized();
    transform..x += dir.x * step ..y += dir.y * step ..z += dir.z * step;
  });
}
```

```dart
// queries stop at four type parameters. State that changes together
// belongs in one component: fewer components per query = fewer lookups
// per entity. Tags cost no slot (require:/exclude:). Additional
// components are readable mid-loop via world.get in O(1). Split state
// into its own component only when it is added/removed independently
// (Stunned) or filtered on.
final class MotionState {
  final Vector3 velocity = Vector3.zero();
  final Vector3 acceleration = Vector3.zero();
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

final class Player implements Tag {      // bit-cheap, filter-only
  const Player();
}

List<Object> playerBundle() => [
  const Player(),                        // present for the entity's whole lifetime
  Health(100),
  const PhysicsDriven(),
  SceneNode(_buildBody()),
];

List<Object> enemyBundle(Node node) => [
  ...combatantBundle(node: node, maxHealth: 40),   // composition = spread
  const Enemy(),
  AggroRange(8),
];
```

```dart
world.add(enemy, const Stunned());   // runtime tag change: the entity leaves
world.remove<Stunned>(enemy);        //   and rejoins exclude:[Stunned] queries
                                     //   at the next frame boundary

final grunt = world.spawn(gruntBundle(at));
world.spawn(weaponBundle(), ownedBy: grunt);   // despawning the owner despawns owned
```

## Scheduling: sets and run conditions

```dart
abstract final class GameSets {
  static const movement = SystemSet('game.movement');
  static const logic = SystemSet('game.logic');
}

// main: order the phases once —
game.configureSets(Schedules.fixedUpdate, [GameSets.movement, GameSets.actions]);
// features: join a phase — never import another feature's systems —
game.addSystem(Schedules.fixedUpdate, movePlayer, inSet: GameSets.movement);
// within a feature: order by function reference — a rename is a compile error
game.addSystem(Schedules.update, applyRecoil, after: [updateShieldState]);
```

```dart
game.addSystem(Schedules.update, resolveHits,
    runIf: inState(GameStatus.playing).and(hasEvents<HitEvent>()));

game.addSystem(Schedules.fixedUpdate, spawnShieldPickups,
    writes: {ShieldPickup},
    // every() is schedule-aware (fixed delta here, frame delta in update) —
    // periodicity lives at registration, never as a timer resource
    runIf: inState(GameStatus.playing).and(every(2.5)));

bool shieldDown(World world) => !world.resource<ShieldState>().active;
    // a custom condition is any bool Function(World)
```

## Events

```dart
void resolveEnemyDeaths(World world) {
  world.query2<Health, SceneTransform>(require: const [Enemy])
      .each((entity, health, transform) {
    if (health.current > 0) return;
    world.emit(EnemyKilled(transform.translation.clone(), 10)); // auto-registers
    world.despawn(entity);
  });
}

void awardBounty(World world) {
  // events since this system's last read, in emission order; the cursor
  // is per-registration. Events are retained for the emitting frame plus
  // one; a gated reader skips older events (reported once by a diagnostic)
  for (final event in world.events<EnemyKilled>()) {
    world.resource<Score>().value += event.bounty;
  }
}
```

```dart
// keep events until every reader consumed them — right for input edges
// that must survive to a fixed step
game.configureEvent<FireReleased>(retainedUpdates: null);
// world.events throws outside a running system; widgets use WorldEventListener
```

## Input

Held state → a `ButtonInput` resource. Discrete intents → events.

```dart
enum GameAction { left, right, fire }

final class FirePressed { const FirePressed(); }
final class FireReleased { const FireReleased(); }

// in a widget: OR-combine sources so releasing one never releases the other;
// setPressed returns the edge it crossed — update + one-shot in one call
switch (input.setPressed(GameAction.fire, spaceDown || touchDown)) {
  case ButtonEdge.pressed:  game.emit(const FirePressed());   // began charging
  case ButtonEdge.released: game.emit(const FireReleased());  // fire exactly once
  case ButtonEdge.none:     break;
}

// in a system: edges exactly once, held state directly
void shootProjectiles(World world) {
  var released = false;
  for (final _ in world.events<FireReleased>()) released = true;
  final charging = world.buttons<GameAction>().pressed(GameAction.fire);
  if (released) world.spawn(projectileBundle(position: muzzle));
}
```

```dart
enum GameAxis { moveX, moveY }

// analog: widget writes the stick, system reads a plain double
axes.setValue(GameAxis.moveX, stick.dx);     // clamped to [-1, 1] by the widget
final x = world.axes<GameAxis>().value(GameAxis.moveX);  // 0.0 if never written
```

```dart
enum CombatAction { roll, attack }

// buffered presses: a roll queued during attack recovery fires the
// instant recovery ends
if (edge == ButtonEdge.pressed) buffer.record(CombatAction.roll);   // widget

void fighterActions(World world) {
  final buffer = world.buffer<CombatAction>();
  // consume removes the oldest unexpired match; the press window (~150ms)
  // expires on wall time, so a freeze does not expire buffered input;
  // call buffer.clear() on stagger
  if (state.recoveryDone && buffer.consume(CombatAction.roll)) {
    startRoll(world);
  }
}
```

## Resources

```dart
final class Score { int value = 0; }

void installScore(GameBuilder game) {
  game.world.insert(Score());
  game.addSystem(Schedules.update, awardKills, reads: const {});
}

void awardKills(World world) {
  for (final event in world.events<EnemyKilled>()) {
    world.resource<Score>().value += event.bounty;
  }
}
// framework state is exposed as members (world.dt, world.clock,
// world.buttons, world.physics, world.gizmos); resource<T>() is for
// game-defined singletons
```

## States

```dart
enum GameStatus { playing, lost }

game.addState<GameStatus>(GameStatus.playing);   // main: one machine per enum;
                                                 //   machines of different
                                                 //   enums are orthogonal
game
  ..addSystem(OnEnter(GameStatus.playing), startRun, reads: const {})
  ..addSystem(Schedules.update, evaluateGameRules,
      reads: {SceneNode}, runIf: inState(GameStatus.playing));

world.setState(GameStatus.lost);     // applies at next frame start:
world.state<GameStatus>();           //   OnExit(old) → OnEnter(new)
```

```dart
List<Object> rockBundle(...) => [
  const DespawnOnExit(GameStatus.playing),   // leave the state → auto-despawn;
  // ...                                     //   no manual cleanup system needed
];
```

## Time

```dart
world.dt            // schedule-aware: fixed delta in fixed schedules,
                    //   frame delta otherwise
world.delta         // frame delta, explicitly
world.fixedDelta    // fixed timestep, explicitly

world.clock.freezeFor(0.06);         // hitstop: 60ms of wall time
world.clock.timeScale = 0.5;         // slow motion — physics, animation and
world.clock.paused = true;           //   gameplay slow together; the fixed
                                     //   step never changes, so fixed-step
                                     //   gameplay stays deterministic
// HUD / camera shake keep moving on FrameTime.unscaledDelta
```

```dart
// gameplay durations live ON COMPONENTS and tick with world.dt — they
// pause, slow and freeze with the game for free
final class EnemyAttack {
  final windup = GameTimer(enemyWindupSeconds);      // one-shot
}

void enemyAttacks(World world) {
  world.query2<EnemyAttack, SceneTransform>().each((entity, attack, transform) {
    attack.windup.tick(world.dt);
    if (!attack.windup.justFinished) return;   // true for exactly one tick
    world.emit(EnemyStruck(entity, transform.translation.clone()));
    attack.windup.reset();                     // re-arms in place; cooldowns
  });                                          //   use the same API: gate on
}                                              //   finished, reset() after acting

final cadence = GameTimer.repeating(1.5);      // wraps in constant time
cadence.tick(world.dt);
for (var i = 0; i < cadence.completionsThisTick; i++) {
  world.spawn(waveBundle());   // completionsThisTick > 1 after a frame hitch
}

final alive = GameStopwatch();                 // counts up: combo windows,
alive.tick(world.dt);                          //   survival score

// DespawnAfter(seconds): the timed sibling of DespawnOnExit — muzzle
// flashes, corpses. System-level cadence → runIf: every(seconds) above.
```

## Physics

```dart
final game = await SceneGame.boot(
  physics: RapierWorld(gravity: Vector3(0, -9.81, 0)),  // any native
  features: [...],                                      //   flutter_scene world
);

void probeGround(World world) {
  final hit = world.physics.raycast(ray, maxDistance: 1.1);  // immediate
}

void damageOnImpact(World world) {
  for (final collision in world.events<EntityCollision>()) { // resolved to
    if (collision.source is! CollisionBegan) continue;       //   entities; one
    hurt(world, collision.a);                                //   frame late
    hurt(world, collision.b);                                //   (async streams)
  }
}

void sweepBlastRadius(World world) {          // synchronous overlap query for
  world.physics.overlapSphereEntities(        //   melee swing, blast radius
      world.resource<SceneNodeIndex>(), blastCenter, blastRadius,
      layerMask: Layers.enemy, includeTriggers: false, (entity, hit) {
    final health = world.tryGet<Health>(entity);
    if (health != null && (health.current -= 25) <= 0) world.despawn(entity);
    return true;                              // false stops early (hit caps)
  });
}
```

## Debug gizmos

```dart
features: [installGizmos(enabled: kDebugMode), ...]   // opt-in render layer

void evaluateHits(World world) {
  world.gizmos.sphere(playerPos, hitRadius, color: GizmoColor.red);
  world.gizmos.ray(playerPos, down, probeDistance, color: GizmoColor.yellow);
}

world.gizmos.enabled = false;   // off = zero draw calls, zero vertex work;
                                //   calls stay in shipping code as no-ops;
                                //   without installGizmos they draw nothing
```

## Testing

```dart
// TestGame runs the exact device pipeline — schedule order, command
// boundaries, clock — no scene, no GPU
final game = TestGame.headless(features: [installCombat]);
game.world.spawn([Health(100), Facing(), FighterState()]);
game.press(CombatAction.roll);
game.pumpFixed(steps: 18);                 // 0.3s at 60Hz, frame-exact
expect(game.world.query<FighterState>().single.$2.iFramed, isTrue);

// pump() = one rendered frame (accumulator-driven fixed steps);
// identical spawns + identical inputs ⇒ identical runs
```

## The rendering bridge

```dart
// the only bridge between world and scene — everything you see is a real Node
SceneNode(node)          // mounted into the scene automatically
SceneTransform.zero()    // when present, synced onto the bound node per frame
const PhysicsDriven()    // a physics body owns the transform instead

// transform on the node directly? NodeTransformOps keeps it allocation-free:
node.setLocalTRS(...);
node.globalTranslationInto(out);
// SceneNodeIndex maps a hit node back to its entity for picking
```

## Packages and examples

| Path | Purpose |
| --- | --- |
| [`packages/scene_dash_v2_core`](packages/scene_dash_v2_core) | Pure-Dart ECS runtime, authoring surface, headless `TestGame`. |
| [`packages/scene_dash_v2`](packages/scene_dash_v2) | `flutter_scene` integration: `SceneGame.boot`, mounting, transform sync, physics bridge, gizmos, widget layer. Re-exports core — one import. |
| [`examples/scene_game`](examples/scene_game) | Complete game: Rapier physics, one feature per folder. |
| [`examples/headless_example`](examples/headless_example) | The core without Flutter. |
| [`examples/scene_benchmark`](examples/scene_benchmark) | On-device render benchmark: static vs mount-only vs ECS vs instanced. |
| [`benchmarks`](benchmarks) | Query, structural, and record-overhead benchmarks. |

```text
examples/scene_game/lib/
├── player/          # each folder: one feature —
├── projectiles/     #   components, bundles, systems, resources
├── rocks/
├── collectables/
├── rules/
├── world/
├── decor/
├── hud/
└── main.dart
```

Deeper docs: [architecture](docs/concept.md) ·
[integration](docs/integration.md) ·

## Development

```bash
flutter pub get                                   # workspace, from the root

cd packages/scene_dash_v2_core && dart test       # engine + surface
cd packages/scene_dash_v2 && flutter test         # integration + widgets
cd examples/scene_game && flutter test            # the game's headless suites
dart analyze                                      # clean, always
```
