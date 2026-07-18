# `flutter_scene` Integration Guide

How Scene-Dash composes with `flutter_scene`: node mounting, transform
authority, scene commands, reaching native engine features, and the
physics bridge. The [README](../README.md) covers the core ECS; this is
the integration detail.

## Lifecycle

`SceneGame.boot` wires the pure-Dart core to a `flutter_scene` scene. On
boot, it:

- exposes the real `Scene` and `SceneCommands` as resources;
- mounts entity-bound `SceneNode` nodes into the scene **before** the
  `update` phase (and once at startup), so a gameplay system never needs a
  `node.parent == null` guard: a queried node is already in the scene;
- syncs optional `SceneTransform` components onto bound nodes;
- exposes a `SceneNodeIndex` resource, the node → entity reverse lookup;
- attaches physics when the `physics:` parameter is given (below);
- exposes `game.onTick` for **your** `SceneView` (the framework never
  constructs one) and drives the scene tick on `GameClock`-scaled time,
  so `timeScale`, `paused`, and `freezeFor` (hitstop) slow or halt physics
  stepping, animations, and gameplay together. Systems that keep moving
  while game time is stopped (HUD, camera shake) read
  `FrameTime.unscaledDelta` instead.

A mounted entity also gains an integration-managed `Mounted` tag (removed
on unmount/despawn) for the rare system that wants to filter on
scene-mounted entities; bundles never author it.

`SceneGame.scene` is non-null, a `SceneGame` always owns a scene (D13);
a real `Scene` needs a Flutter GPU context, so this boot fails fast
without one. A widget tree over a *scene-less* world (editor panels,
widget-test harnesses) is a different type, `WorldGame.boot(...)`: same
physics and gameplay wiring, same `onTick`-driven frames, no scene member
at all. Pure-logic suites with no widget tree want the core package's
`TestGame.headless` instead.

## Direct node path: mutate nodes yourself

The starter example uses `SceneTransform` because it is the easiest path
to understand. When you want to avoid duplicated transform state, store a
`SceneNode` and mutate the native `flutter_scene` node directly:

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
    binding.node.localTransform.setTranslationRaw(
      orbit.radius * cos(orbit.phase),
      0,
      orbit.radius * sin(orbit.phase),
    );
    binding.node.markTransformDirty();
  });
}
```

The ECS stores the node reference directly and mutates the native node,
which keeps visual-only state where `flutter_scene` already holds it.

> **Access-metadata rule:** mutating an object reached through a component
> (a `Node` or a Rapier body behind `SceneNode`) counts as *writing* that
> component for scheduling diagnostics. The scheduler runs sequentially
> and cannot infer transitive mutations, so register with
> `writes: {SceneNode}` whenever a system changes the referenced node or
> its native components.

Two idioms recur on this path: a node matrix must be *reassigned* (or
marked) after an in-place edit so the dirty flag trips, and
`getTranslation()` allocates a fresh vector per call. The
`NodeTransformOps` extension encodes both once, so per-frame systems
neither rediscover the rules nor allocate:

```dart
node.setLocalTRS(x, y, z, sx, sy, sz);   // rebuild translate+scale in place
node.setLocalUniform(0, bob, 0, pulse);  // one uniform scale
node.globalTranslationInto(scratch);     // world position, no allocation
```

(The orbit example above edits translation *within* an existing rotation,
so it uses `setTranslationRaw` + `markTransformDirty` directly;
`setLocalTRS` rebuilds the whole matrix.)

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

`SceneTransform` is a local translation/rotation/scale component with a
complete gameplay API: translation (`setTranslation`, `translate`), scale
(`setScale`, `setUniformScale`), rotation (`setRotationX/Y/Z`,
`setRotationEuler`, `setRotationAxisAngle`, `setRotation`, and relative
`rotate`/`rotateX/Y/Z`), `lookAt`, copy/reset (`setFrom`, `setIdentity`),
and a matrix escape hatch (`setFromMatrix`, `toMatrix`). Angles are
radians; forward is −Z and up is +Y. The fields stay directly mutable, so
there is no dirty tracking; helper calls and direct field mutation are
equivalent.

The integration writes it onto the bound node during
`Schedules.renderSync`. Add `PhysicsDriven` to entities whose node
transform is owned by physics or another authority, so generic sync skips
them.

Games with a different transform type can use `CustomSceneSyncPlugin<T>`
and provide either a translation callback or a full matrix writer.

## Scene commands

Use `SceneCommands` for deferred scene-graph mutations from systems:

```dart
void addDecoration(World world) {
  world.resource<SceneCommands>().add(Node());
}
```

## Using flutter_scene directly

Scene-Dash deliberately does **not** wrap `flutter_scene`. New engine
features become usable through two access points it already gives you, so
there is no bridge layer to keep in sync with each `flutter_scene`
release:

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
build visuals: headless boots (tests) skip them at the schedule, the body
reads the scene unconditionally, and the dependency sits in the manifest
next to `reads:`/`writes:` instead of repeating as a guard in every body.
The example game gates every `vfx` spawn system this way.

### Picking: `SceneNodeIndex` (node → entity)

`SceneNode` is entity → node. `Scene.raycast` and `ScenePointer` return a
`Node`, so to act on the entity you hit, read the `SceneNodeIndex`
resource the integration maintains. `entityOf` walks up ancestors, so a
hit on a child mesh still resolves to the bound entity:

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

### Hardware instancing: many visuals, one draw call

For many identical visuals (foliage, debris, particles), an
`InstancedMesh` (one node, one draw call) beats one entity/node each. A
startup system builds it on the scene; an update system animates the
instances **allocation-free** by reusing a single scratch matrix
(`setInstanceTransform` copies it in):

```dart
void animateMotes(World world) {
  final field = world.resource<MoteField>();
  final mesh = field.mesh;
  final scratch = field.scratch; // one Matrix4, reused every instance & frame
  for (var i = 0; i < field.count; i++) {
    scratch.setTranslationRaw(field.x[i], field.bob(i, world.dt), field.z[i]);
    mesh.setInstanceTransform(i, scratch);
  }
}
```

See [`examples/scene_game/lib/decor/`](../examples/scene_game/lib/decor)
for the full feature.

## Debug gizmos

The gizmo render layer is opt-in; add it to the feature list:

```dart
final game = await SceneGame.boot(
  features: [installGizmos(enabled: showDebugGizmos), ...],
);
```

`world.gizmos` then provides immediate-mode debug drawing: any system
submits shapes for the current frame and nothing persists.

```dart
void probeGround(World world) {
  world.gizmos
    ..ray(origin, down, probeDistance, color: GizmoColor.yellow)
    ..sphere(playerPos, hitRadius, color: GizmoColor.red)
    ..line(from, to)
    ..cuboid(center, halfExtents);
}
```

Submissions are cleared at frame start and flushed into instanced pools
at `renderSync`, write plain floats (no allocation), and become
early-return no-ops while `gizmos.enabled` is `false`. The pools build
lazily on the first *enabled* frame and hide when the flag goes off, so
`enabled` is a true runtime toggle: a disabled layer costs zero draw calls
and zero vertex work. Games that never install the layer still call
`world.gizmos` safely; it falls back to a disabled recorder. The palette is a fixed
four-color enum because 0.18 instancing is transform-only: each color is
its own pool; per-call arbitrary colors would mean one draw per gizmo.
Overflow past a shape's per-color capacity drops the shape and counts it
in `droppedThisFrame`.

## Physics and collisions

Scene-Dash does not implement physics. Hand `SceneGame.boot` the native
`flutter_scene` `PhysicsWorld` you want; it is attached to the scene graph
and bridged into the ECS:

```dart
final game = await SceneGame.boot(
  physics: RapierWorld(gravity: Vector3(0, -9.81, 0)),
  features: [installGameplay],
);
```

`BasicPhysicsWorld` is useful for picking, raycasts, overlap checks,
trigger events, and kinematic-only gameplay. It does not simulate dynamic
rigid bodies. For full rigid-body contact response, use a backend world
such as `flutter_scene_rapier`; the bridge works through the same
`PhysicsWorld` interface either way.

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

Overlap results name scene nodes, so gameplay code would otherwise repeat
the same preamble on every hit: check the collider's layer, call
`SceneNodeIndex.entityOf`, skip the misses. `overlapSphereEntities` and
`overlapBoxEntities` do that resolution once and deliver each hit's
*entity* (plus the raw `OverlapHit`) to a callback:

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

Semantics worth knowing:

- Hits whose node (and ancestors) is not entity-bound are skipped; use
  the raw `overlapSphere` when unmanaged geometry matters.
- `layerMask` is passed to the backend *and* re-checked result-side
  against the abstract `Collider.collisionLayer`, covering backends that
  accept the parameter without forwarding it natively
  (`flutter_scene_rapier` 0.2.x).
- A node carrying several colliders on the queried layer delivers once per
  collider; per-entity dedup belongs to the consumer (the per-swing set
  above).
- The extension types only against the abstract `PhysicsWorld`/`Collider`
  contract from core `flutter_scene`, so every backend works unchanged.

This is the synchronous counterpart of the collision *events* below:
overlap queries resolve inside the running system (melee swings, blast
radii), while collision events arrive the following frame.

### Collision events

The physics bridge registers `CollisionEvent` as an ECS event and drains
the native async stream at `Schedules.frameStart`; on top of it, each
collision's nodes are resolved back to entities once and republished as
`EntityCollision`, so systems never repeat the node-to-entity lookup:

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

Events arrive a frame late, a platform constraint rather than a scheduling
choice: `flutter_scene`'s collision streams are async, so a contact from
frame N's physics is only readable in frame N+1.

For larger games, treat raw collision data as a bridge boundary. Keep
gameplay semantics in your own components and resources (layers, teams,
sensors, hitboxes, damage) and translate physics events or query results
into game-specific events (`world.emit(HitLanded(...))`). That keeps the
physics backend swappable: Scene-Dash owns scheduling, resources, events,
and queries; `flutter_scene` and the selected backend own colliders,
bodies, raycasts, overlap checks, and collision generation.
