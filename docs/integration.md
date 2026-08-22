# `flutter_scene` Integration Guide

Node mounting, transform authority, scene commands, reaching native
engine features, and the physics bridge. The [README](../README.md)
covers the core ECS. Rendering, cameras, physics and widgets stay native
`flutter_scene` APIs.

## Lifecycle

`SceneGame.boot` wires the pure-Dart core to a `flutter_scene` scene. On
boot, it:

- exposes the real `Scene` and `SceneCommands` as resources
- mounts entity-bound `SceneNode` nodes into the scene **before** the
  `update` phase, and once at startup, so a queried node is already in
  the scene and no system needs a `node.parent == null` guard
- syncs optional `SceneTransform` components onto bound nodes
- exposes a `SceneNodeIndex` resource, the node to entity reverse lookup
- attaches physics when the `physics:` parameter is given (below)
- exposes `game.onTick` for **your** `SceneView`, which the framework
  never constructs

The scene tick runs on `GameClock` time, so `timeScale`, `paused` and
`freezeFor` slow or stop physics, animation and gameplay together. HUD
and camera shake, which should keep moving anyway, read
`FrameTime.unscaledDelta`.

A mounted entity also gets a `Mounted` tag, which goes away on unmount or
despawn. It is there if you ever want to query for what is in the scene.
Your bundles never add it.

A `SceneGame` always owns a scene, so `SceneGame.scene` is never null. A
real `Scene` needs a Flutter GPU context, so boot fails fast without one.
For a widget tree over a world with no scene, editor panels or widget
tests, use `WorldGame.boot(...)` instead. Same physics and gameplay
wiring, same `onTick`-driven frames, no scene. For pure logic with no
widget tree, use the core package's `TestGame.headless`.

## Direct node path: mutate nodes yourself

To avoid duplicated transform state, store a `SceneNode` and mutate the
native `flutter_scene` node directly:

```dart
final class Orbit {
  final double radius;
  final double speed;
  double phase;

  Orbit({required this.radius, required this.speed, required this.phase});
}

List<Object> cubeBundle({required double phase}) => [
  Orbit(radius: 3, speed: 1, phase: phase),
  SceneNode(Node(mesh: cubeMesh)),
];

void orbitNodes(World world) {
  // Mutating the node through SceneNode counts as writing SceneNode.
  world.query2<Orbit, SceneNode>().each((entity, orbit, binding) {
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
```

> **Access-metadata rule:** changing something you reached *through* a
> component, a `Node` or a Rapier body behind `SceneNode`, still counts
> as writing that component. Register with `writes: {SceneNode}` whenever
> a system touches the node or its native components.

Two traps on this path. A node matrix must be reassigned, or marked,
after an in-place edit, or the dirty flag never trips. And
`getTranslation()` allocates a fresh vector per call. `NodeTransformOps`
handles both:

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

`SceneTransform` holds a local position, rotation and scale, with the
usual move, rotate, scale and `lookAt` helpers and a way in and out of a
raw matrix. Angles are radians, forward is +Z, up is +Y. The fields are
plain and mutable, so writing one directly is the same as calling a
helper.

It gets written onto the bound node during `Schedules.renderSync`. Add
`PhysicsDriven` when physics or something else owns the transform
instead, and the sync skips that entity.

Got your own transform type? `CustomSceneSyncPlugin<T>` takes either a
translation callback or a full matrix writer.

## Scene commands

Use `SceneCommands` for deferred scene-graph mutations from systems:

```dart
void addDecoration(World world) {
  world.resource<SceneCommands>().add(Node());
}
```

## Using flutter_scene directly

Scene-Dash does **not** wrap `flutter_scene`. New engine features reach
you through two access points:

- **Scene-wide features → the `Scene` resource.** A startup system
  mutates the live scene directly.
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

`runIf: hasResource<Scene>()` is the standard shape for systems that
build visuals. Headless boots skip them, so the body can read the scene
without a guard.

### Picking: `SceneNodeIndex` (node → entity)

`SceneNode` gets you entity → node. `Scene.raycast` and `ScenePointer`
hand back a `Node`, so go the other way through the `SceneNodeIndex`
resource. `entityOf` walks up parents, so hitting a child mesh still
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

Scene-Dash does not implement physics. Hand `SceneGame.boot` the native
`flutter_scene` `PhysicsWorld` you want. It is attached to the scene graph
and bridged into the ECS:

```dart
final game = await SceneGame.boot(
  physics: RapierWorld(gravity: Vector3(0, -9.81, 0)),
  features: [installGameplay],
);
```

`BasicPhysicsWorld` covers picking, raycasts, overlap checks, triggers
and kinematic gameplay. It does not simulate dynamic rigid bodies. For
those, use a backend like `flutter_scene_rapier`. The bridge is the same
either way.

Physics objects live on the `flutter_scene` node. The ECS entity stores a
`SceneNode`, plus `PhysicsDriven` when physics owns the transform:

```dart
List<Object> playerBodyBundle() => [
  const Player(),
  SceneNode(
    Node(mesh: playerMesh)
      ..addComponent(RapierRigidBody(type: BodyType.dynamic_))
      ..addComponent(
        RapierCollider(
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

Systems reach the native world as `world.physics` for immediate scene
queries:

```dart
// Reused scratch so the per-step probe allocates nothing.
final Vector3 _origin = Vector3.zero();

void probeGround(World world) {
  final player = world.query<SceneNode>(require: const [Player]).firstOrNull;
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
`overlapBoxEntities` resolve them and hand each hit's *entity*, plus the
raw `OverlapHit`, to a callback:

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

- Hits whose node and ancestors are not entity-bound are skipped. Use the
  raw `overlapSphere` when unmanaged geometry matters.
- `layerMask` goes to the backend and is checked again on the results,
  because some backends take the parameter without actually using it
  (`flutter_scene_rapier` 0.2.x).
- A node with several colliders on that layer fires once per collider.
  Deduping per entity is your job, like the per-swing set above.

This is the immediate version of the collision *events* below. An overlap
query answers inside the system that ran it, which is what a melee swing
or a blast radius needs. Collision events land the following frame.

### Collision events

The bridge drains the native collision stream at `Schedules.frameStart`
and publishes it as `CollisionEvent`. It also looks each collision's
nodes back up to entities once and republishes that as
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

Collision events arrive a frame late: the native streams are async.

In a bigger game, stop at the bridge. Keep the gameplay meaning in your
own components and resources, things like layers, teams, sensors,
hitboxes and damage, and turn physics events into your own events with
`world.emit(HitLanded(...))`. Then swapping the physics backend stays a
small job.
