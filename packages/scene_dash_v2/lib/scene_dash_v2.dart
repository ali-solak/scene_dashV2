/// Scene-Dash v2: the `flutter_scene` integration package.
///
/// Wires the headless core (`scene_dash_v2_core`) to the `flutter_scene`
/// lifecycle:
///
/// * [Game] — the internal engine facade wrapping an `App`, attaching the
///   scene driver and exposing `onTick` for `SceneView` (Phase 2 wraps it in
///   `SceneGame.boot`);
/// * [SceneTransform] / [SceneNode] / [PhysicsDriven] — bind entities to
///   nodes and mark physics-owned transforms; the driver syncs
///   [SceneTransform]'s local translation, rotation and scale and mounts
///   bound nodes automatically ([CustomSceneSyncPlugin] covers non-standard
///   transform types);
/// * [SceneCommands] — deferred scene-graph mutations;
/// * [PhysicsPlugin] / [PhysicsEventBridge] — optional one-world convenience
///   for exposing a generic `PhysicsWorld` resource and buffering raw
///   `CollisionEvent`s into ECS events;
/// * [EntityCollisionPlugin] / [EntityCollision] — an optional layer on top
///   that resolves each collision's nodes back to entities;
/// * [EntityOverlapQueries] — `overlapSphereEntities` / `overlapBoxEntities`
///   extensions on `PhysicsWorld`: immediate overlap queries delivered as
///   entities;
/// * [Gizmos] — immediate-mode debug shapes.
///
/// Re-exports the core user surface, so game code needs exactly one import.
/// Imports `package:flutter_scene/scene.dart` (note: the 0.18.x library is
/// `scene.dart`, not `flutter_scene.dart`).
library;

export 'package:scene_dash_v2_core/advanced.dart' show EcsFrameLoop;
export 'package:scene_dash_v2_core/scene_dash_v2_core.dart';

export 'src/entity_collision.dart';
export 'src/entity_queries.dart';
export 'src/game.dart';
export 'src/game_scope.dart';
export 'src/gizmos.dart';
export 'src/node_transform_ops.dart';
export 'src/physics_event_bridge.dart';
export 'src/physics_plugin.dart';
export 'src/scene_commands.dart';
export 'src/scene_game.dart';
export 'src/scene_mount.dart';
export 'src/scene_node_index.dart';
export 'src/scene_node.dart';
export 'src/scene_sync.dart';
export 'src/world_inspector.dart';
export 'src/world_scene_extensions.dart';
export 'src/world_widgets.dart';
export 'src/scene_transform.dart';
