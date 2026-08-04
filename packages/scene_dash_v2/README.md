# Scene-Dash v2

![Scene-Dash v2: the combat sample](https://raw.githubusercontent.com/ali-solak/scene_dashV2/main/combat_sample_game.gif)

<p align="center">
  <a title="Pub" href="https://pub.dev/packages/scene_dash_v2"><img src="https://img.shields.io/pub/v/scene_dash_v2.svg?label=scene_dash_v2&style=popout"/></a>
  <a title="Pub" href="https://pub.dev/packages/scene_dash_v2_core"><img src="https://img.shields.io/pub/v/scene_dash_v2_core.svg?label=scene_dash_v2_core&style=popout"/></a>
  <a title="CI" href="https://github.com/ali-solak/scene_dashV2/actions/workflows/ci.yaml?query=branch%3Amain"><img src="https://github.com/ali-solak/scene_dashV2/actions/workflows/ci.yaml/badge.svg?branch=main"/></a>
  <img src="https://img.shields.io/badge/license-MIT-blue.svg"/>
</p>

An ECS-based way to organize, coordinate, and headlessly test gameplay code
built on top of [`flutter_scene`](https://pub.dev/packages/flutter_scene). ECS is
the implementation model. the purpose is keeping a growing game's features,
state, lifecycles, and tests understandable.

## World-reactive widgets

A widget selects one value out of the world and rebuilds only when that
value changes:

```dart
EntityBuilder<Health, double>(
  entity: player,
  select: (h) => h.current,                 // compared once per frame
  builder: (context, hp) => HealthBar(hp),  // runs only when it changed
  absent: const RespawnCountdown(),         // entity dead / component gone
)
```

Same frame tick, same select-and-compare:

```dart
WorldBuilder<int>(select: (w) => w.query<Health>(require: const [Enemy]).count(),
    builder: (ctx, n) => Text('$n enemies'))     // any world-derived value

GameStateBuilder<GameStatus>(builder: (ctx, s) => switch (s) { ... })
                                                 // a subtree per game state

WorldEventListener<EnemyKilled>(onEvent: (ctx, e) => shakeScore(ctx),
    child: const ScorePanel())                   // world events into UI
```

[The rest of the widget layer](https://github.com/ali-solak/scene_dashV2/blob/main/docs/reference.md#world-reactive-widgets):
`.matching` resolves the entity through the world, `.pulse` drives transient
feedback, `every:` throttles a heavy select, `GameScope` reaches the game
from any `context`.

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
  NodeRef(Node(mesh: Mesh(CuboidGeometry(Vector3.all(0.8)), UnlitMaterial()))),
];
```

Hot reload applies edits to system bodies; there is no build step.

## Quick start

```bash
flutter channel master          # flutter_scene needs Flutter GPU
flutter pub get                 # resolve the workspace (repo root)
cd examples/combat_sample
flutter run --enable-flutter-gpu
```

## Reference

[docs/reference.md](https://github.com/ali-solak/scene_dashV2/blob/main/docs/reference.md)

- UI
  - [World-reactive widgets](https://github.com/ali-solak/scene_dashV2/blob/main/docs/reference.md#world-reactive-widgets)
    - [GameScope](https://github.com/ali-solak/scene_dashV2/blob/main/docs/reference.md#gamescope)
- Boot
  - [Application setup](https://github.com/ali-solak/scene_dashV2/blob/main/docs/reference.md#application-setup)
  - [Features and systems](https://github.com/ali-solak/scene_dashV2/blob/main/docs/reference.md#features-and-systems)
- World
  - [Components, tags, bundles](https://github.com/ali-solak/scene_dashV2/blob/main/docs/reference.md#components-tags-bundles)
  - [Queries](https://github.com/ali-solak/scene_dashV2/blob/main/docs/reference.md#queries)
  - [Node lookups](https://github.com/ali-solak/scene_dashV2/blob/main/docs/reference.md#node-lookups)
  - [Resources](https://github.com/ali-solak/scene_dashV2/blob/main/docs/reference.md#resources)
- Frame
  - [Scheduling: sets and run conditions](https://github.com/ali-solak/scene_dashV2/blob/main/docs/reference.md#scheduling-sets-and-run-conditions)
  - [Time](https://github.com/ali-solak/scene_dashV2/blob/main/docs/reference.md#time)
- Coordination
  - [Events](https://github.com/ali-solak/scene_dashV2/blob/main/docs/reference.md#events)
  - [Input](https://github.com/ali-solak/scene_dashV2/blob/main/docs/reference.md#input)
  - [States](https://github.com/ali-solak/scene_dashV2/blob/main/docs/reference.md#states)
  - [Machine](https://github.com/ali-solak/scene_dashV2/blob/main/docs/reference.md#machine)
- flutter_scene
  - [Physics](https://github.com/ali-solak/scene_dashV2/blob/main/docs/reference.md#physics)
  - [The rendering bridge](https://github.com/ali-solak/scene_dashV2/blob/main/docs/reference.md#the-rendering-bridge)
- Tooling
  - [Debugging](https://github.com/ali-solak/scene_dashV2/blob/main/docs/reference.md#debugging)
    - [Entity debug](https://github.com/ali-solak/scene_dashV2/blob/main/docs/reference.md#entity-debug)
    - [Gizmo debug](https://github.com/ali-solak/scene_dashV2/blob/main/docs/reference.md#gizmo-debug)
    - [Inspector](https://github.com/ali-solak/scene_dashV2/blob/main/docs/reference.md#inspector)
  - [Testing](https://github.com/ali-solak/scene_dashV2/blob/main/docs/reference.md#testing)

[docs/concept.md](https://github.com/ali-solak/scene_dashV2/blob/main/docs/concept.md) for the architecture,
[docs/integration.md](https://github.com/ali-solak/scene_dashV2/blob/main/docs/integration.md) for the `flutter_scene` bridge.

## Packages and examples

| Path | Purpose |
| --- | --- |
| [`packages/scene_dash_v2_core`](https://github.com/ali-solak/scene_dashV2/blob/main/packages/scene_dash_v2_core) | Pure-Dart ECS runtime, authoring surface, headless `TestGame`. |
| [`packages/scene_dash_v2`](https://github.com/ali-solak/scene_dashV2/blob/main/packages/scene_dash_v2) | `flutter_scene` integration: `SceneGame.boot`, mounting, transform sync, physics bridge, gizmos, widget layer. Re-exports core, so one import covers both. |
| [`packages/scene_dash_inspector`](https://github.com/ali-solak/scene_dashV2/blob/main/packages/scene_dash_inspector) | Optional debug overlay: live entities, resources, system timings, event channels. Read-only, polled at 4 Hz. |
| [`examples/scene_game`](https://github.com/ali-solak/scene_dashV2/blob/main/examples/scene_game) | Complete game: Rapier physics, one feature per folder. |
| [`examples/headless_example`](https://github.com/ali-solak/scene_dashV2/blob/main/examples/headless_example) | The core without Flutter. |
| [`examples/scene_benchmark`](https://github.com/ali-solak/scene_dashV2/blob/main/examples/scene_benchmark) | On-device render benchmark: static vs mount-only vs ECS vs instanced. |
| [`examples/combat_sample`](https://github.com/ali-solak/scene_dashV2/blob/main/examples/combat_sample) | Combat slice: KayKit knight against waves of barbarians, lock-on, buyable skills, giants, Rapier ragdolls, authored `.fmat` materials. Gameplay pinned headless. |
| [`benchmarks`](https://github.com/ali-solak/scene_dashV2/blob/main/benchmarks) | Query, structural, and record-overhead benchmarks. |

```text
examples/scene_game/lib/features/   # feature based structure
├── player/                         #   else you keep beside it (hud/, fx/,
├── projectiles/                    #   common/, main.dart) is your call
├── rocks/
├── collectables/
├── rules/
├── world/
└── decor/

examples/scene_game/lib/features/player/     # every feature, same shape
├── player.dart      # the Feature function: installs this feature's systems
├── data/            # components, bundles, config, resources
├── systems/         # one file per concern, not one file per feature
└── animation/       # optional; clip selection lives with its feature
```
