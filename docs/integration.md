# `flutter_scene` Integration Guide

How entities get into the scene, who owns a transform, scene commands,
using native engine features, and the physics bridge. The
[reference](reference.md) covers the core ECS. Rendering, cameras, physics
and widgets stay plain `flutter_scene` APIs.

## Lifecycle

`SceneGame.boot` wires the pure-Dart core to a `flutter_scene` scene. On
boot, it:

- exposes the real `Scene` and `SceneCommands` as resources
- mounts entity-bound `NodeRef` nodes into the scene **before** the
  `update` phase, and once at startup, so a queried node is already in
  the scene and no system needs a `node.parent == null` guard
- syncs optional `SceneTransform` components onto bound nodes
- exposes a `SceneNodeIndex` resource, the node to entity reverse lookup
- attaches physics when the `physics:` parameter is given (below)
- exposes `game.onTick` for **your** `SceneView`, which the framework
  never constructs

The scene ticks on `GameClock` time, so `timeScale`, `paused` and
`freezeFor` slow or stop physics, animation and gameplay together. The
HUD and camera shake should keep moving anyway, so they read
`FrameTime.unscaledDelta`.

A mounted entity also gets a `Mounted` tag. It goes away on unmount or
despawn. Use it if you want to query for what is in the scene. Your
bundles never add it.

A `SceneGame` always owns a scene, so `SceneGame.scene` is never null. A
real `Scene` needs a Flutter GPU context, so boot fails right away without
one. For a widget tree over a world with no scene, like editor panels or
widget tests, use `WorldGame.boot(...)` instead. It has the same physics
and gameplay wiring and the same `onTick`-driven frames, just no scene.
For pure logic with no widget tree, use the core package's
`TestGame.headless`.

## Direct node path: change nodes yourself

To avoid keeping transform state twice, store a `NodeRef` and change the
native `flutter_scene` node directly:

```dart doc-test:node_binding
import 'dart:math';
import 'package:flutter_scene/scene.dart' show Node;
import 'package:scene_dash_v2/scene_dash_v2.dart';

final class Orbit {
  final double radius;
  final double speed;
  double phase;

  Orbit({required this.radius, required this.speed, required this.phase});
}

List<Object> cubeBundle(Node node, {required double phase}) => [
  Orbit(radius: 3, speed: 1, phase: phase),
  NodeRef(node),
];

void orbitNodes(World world) {
  // Mutating the node through NodeRef counts as writing NodeRef.
  world.query2<Orbit, NodeRef>().each((entity, orbit, binding) {
    orbit.phase += orbit.speed * world.dt;
    binding.node.mutateLocalTransform(
      (m) => m.setTranslationRaw(
        orbit.radius * cos(orbit.phase),
        0,
        orbit.radius * sin(orbit.phase),
      ),
    );
  });
}

Future<void> main() async {
  final game = await WorldGame.boot(features: [
    (g) => g.addSystem(Schedules.update, orbitNodes, writes: {Orbit, NodeRef}),
  ]);
  // Supply a mesh-bearing node from your scene in a rendered application.
  game.world.spawn(cubeBundle(Node(), phase: 0));
  game.onTick(const Duration(milliseconds: 16), 1 / 60);
  await game.shutdown();
}
```

> **Access-metadata rule:** changing something you reached *through* a
> component, a `Node` or a Rapier body behind `NodeRef`, still counts
> as writing that component. Register with `writes: {NodeRef}` whenever
> a system touches the node or its native components.

This path has two traps. After editing a node's matrix in place, you must
reassign it or mark it dirty, or the change never shows. And
`getTranslation()` allocates a new vector on every call.
`NodeTransformOps` handles both:

```dart
node.setLocalTRS(x, y, z, sx, sy, sz);   // rebuild translate+scale in place
node.setLocalUniform(0, bob, 0, pulse);  // one uniform scale
node.globalTranslationInto(scratch);     // world position, no allocation
```

The orbit example edits translation inside an existing rotation, so it
uses `setTranslationRaw` directly. `setLocalTRS` rebuilds the whole
matrix.

## ECS-owned transforms

Use `SceneTransform` when the ECS should own transform state: networking,
serialization, headless simulation, rollback, save files, or renderer
independence.

```dart
final transform = SceneTransform.zero()
  ..setTranslation(0, 1, 0)
  ..setRotationY(angle)
  ..setUniformScale(1.5);
```

`SceneTransform` holds a local position, rotation and scale. It has the
usual move, rotate, scale and `lookAt` helpers, and converts to and from a
raw matrix. Angles are in radians, forward is +Z, up is +Y. The fields are
plain and mutable, so writing one directly does the same as calling a
helper.

It is copied onto the bound node during `Schedules.renderSync`. If physics
or something else owns the transform instead, add `PhysicsDriven` and the
sync skips that entity.

Have your own transform type? `CustomSceneSyncPlugin<T>` takes either a
translation callback or a full matrix writer.

## Scene commands

Use `SceneCommands` to queue scene-graph changes from systems:

```dart
void addDecoration(World world) {
  world.resource<SceneCommands>().add(Node());
}
```

## Using flutter_scene directly

Scene-Dash does **not** wrap `flutter_scene`. You reach new engine
features in one of two places:

- **Scene-wide features → the `Scene` resource.** A startup system
  changes the live scene directly.
- **Per-entity features → the `Node` your bundle builds.** Add components
  and configure materials on that node like any `flutter_scene` app.

| flutter_scene feature | Reach it via |
| --- | --- |
| `antiAliasingMode` (FXAA/auto), `renderScale`, `filterQuality` | the `Scene` resource |
| `ambientOcclusion`, `skybox`, `skyEnvironment`, `postProcess` | the `Scene` resource |
| Offscreen render targets (`scene.views`, `RenderTexture`) | the `Scene` resource |
| `Scene.raycast` / `ScenePointer` visual picking | `Scene` + `SceneNodeIndex` |
| `WidgetComponent` (live in-world widget) + auto input | bundle `Node` component |
| `RenderTexture` in a material slot (monitor/mirror) | bundle `Node` material |
| `InstancedMesh`, `UnlitMaterial.alphaMode`, `Node.raycastable` | bundle `Node` |
| GLB models (`Node.fromGlbAsset`, `loadScene`) | startup load → resource → bundles |

### Scene-wide settings from a startup system

```dart
// Registration: gate on the scene so headless boots skip the system.
game.addSystem(Schedules.startup, setupScene,
    reads: const {}, runIf: hasResource<Scene>());

void setupScene(World world) {
  final scene = world.resource<Scene>();
  scene
    ..antiAliasingMode = AntiAliasingMode.auto // MSAA where supported, else FXAA
    ..renderScale = 1.0                        // <1.0 faster, >1.0 supersamples
    ..skybox = Skybox(GradientSkySource());
  scene.ambientOcclusion
    ..enabled = true
    ..intensity = 1.1;
}
```

Use `runIf: hasResource<Scene>()` on every system that builds visuals.
Boots without a scene skip those systems, so the body can read the scene
without a null check.

### Picking: `SceneNodeIndex` (node → entity)

`NodeRef` goes from entity to node. `Scene.raycast` and `ScenePointer`
give you a `Node`, so go back the other way through the `SceneNodeIndex`
resource. `entityOf` walks up the parents, so a hit on a child mesh still
finds the entity that owns it:

```dart
void pick(World world) {
  final scene = world.resource<Scene>();
  final request = world.resource<PickRequest>(); // your own resource holding a ray
  final hit = scene.raycast(request.ray);
  if (hit == null) return;
  final entity = world.resource<SceneNodeIndex>().entityOf(hit.node);
  if (entity != null) {
    // act on the entity (read components, defer structural changes, ...)
  }
}
```

## Physics and collisions

Scene-Dash has no physics of its own. Pass `SceneGame.boot` the native
`flutter_scene` `PhysicsWorld` you want. It gets attached to the scene
graph and connected to the ECS:

```dart
final game = await SceneGame.boot(
  physics: PhysicsWorld(RapierWorld(gravity: Vector3(0, -9.81, 0))),
  features: [installGameplay],
);
```

`PhysicsWorld` takes a backend. `BasicSimulation()` from `flutter_scene`
covers picking, raycasts, overlap checks, triggers and kinematic gameplay
in pure Dart. For dynamic rigid bodies, use `RapierWorld()` from
`flutter_scene_rapier`. The bridge is the same either way.

Physics objects live on the `flutter_scene` node. The ECS entity stores a
`NodeRef`, plus `PhysicsDriven` when physics owns the transform:

```dart
List<Object> playerBodyBundle() => [
  const Player(),
  NodeRef(
    Node(mesh: playerMesh)
      ..addComponent(RigidBody(type: BodyType.dynamic_))
      ..addComponent(
        Collider(
          shape: SphereShape(radius: 0.5),
          collisionLayer: Layers.player,
          collisionMask: Layers.world | Layers.pickup,
        ),
      ),
  ),
  // Skip generic SceneTransform sync; the physics body/node is authoritative.
  const PhysicsDriven(),
];
```

Systems reach the native physics world through `world.physics` for scene
queries that answer right away:

```dart
// Reused scratch so the per-step probe allocates nothing.
final Vector3 _origin = Vector3.zero();

void probeGround(World world) {
  final player = world.query<NodeRef>(require: const [Player]).firstOrNull;
  if (player == null) return;
  player.$2.node.globalTranslationInto(_origin);
  final ground = world.physics.raycast(
    Ray.originDirection(_origin, Vector3(0, -1, 0)),
    maxDistance: 2,
    layerMask: Layers.world,
    includeTriggers: false,
  );

  if (ground == null) {
    // The player is airborne or falling.
  }
}
```

### Entity-carrying overlap queries

Overlap results name scene nodes. `overlapSphereEntities` and
`overlapBoxEntities` look those nodes up and pass each hit's *entity*,
plus the raw `OverlapHit`, to a callback:

```dart
void meleeSwing(World world) {
  final swing = world.resource<ActiveSwing>(); // your own resource: arc, damage, hit set
  world.physics.overlapSphereEntities(
      world.resource<SceneNodeIndex>(), swing.center, swing.radius,
      layerMask: Layers.enemy, includeTriggers: false, (entity, hit) {
    if (!swing.alreadyHit.add(entity)) return true; // once per swing
    world.tryGet<Health>(entity)?.current -= swing.damage;
    return true; // false stops the scan early (per-swing hit caps)
  });
}
```

Worth knowing:

- A hit is skipped if neither its node nor any parent is bound to an
  entity. Use the raw `overlapSphere` when geometry without entities
  matters.
- `layerMask` is passed to the backend and checked again on the results,
  because some backends accept it without using it
  (`flutter_scene_rapier` 0.5.x).
- A node with several colliders on that layer fires once per collider.
  Removing duplicates per entity is up to you, like the per-swing set
  above.

This is the instant version of the collision *events* below. An overlap
query answers inside the system that asked, which is what a melee swing
or a blast radius needs. Collision events arrive on the next frame.

### Collision events

At `Schedules.frameStart` the bridge reads everything waiting on the
native collision stream and emits it as `CollisionEvent`. It also looks
up the entity for each collision's nodes once and emits that as
`EntityCollision`, so your systems never do the lookup themselves:

```dart
void damageOnImpact(World world) {
  for (final collision in world.events<EntityCollision>()) {
    if (collision.source is! CollisionBegan) continue;   // ignore separations
    _hurt(world, collision.a);
    _hurt(world, collision.b);
  }
}

void _hurt(World world, Entity? entity) {
  if (entity == null) return;                 // unbound collider (level geometry)
  final health = world.tryGet<Health>(entity); // null unless this side has Health
  if (health == null) return;
  health.current -= 10;
  if (health.current <= 0) world.despawn(entity);
}
```

Collision events arrive one frame late, because the native streams are
async.

In a bigger game, keep physics at the edge. Put the gameplay meaning
(layers, teams, sensors, hitboxes, damage) in your own components and
resources, and turn physics events into your own events with
`world.emit(HitLanded(...))`. Then swapping the physics backend stays a
small job.
