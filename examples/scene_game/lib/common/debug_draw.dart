import 'package:flutter_scene/kit.dart' show DebugDraw;
import 'package:flutter_scene/scene.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';
import 'package:vector_math/vector_math.dart';

import '../hud/debug_panel.dart';

abstract final class DebugColors {
  static final Vector4 red = Vector4(1.0, 0.3, 0.25, 1);
  static final Vector4 blue = Vector4(0.35, 0.65, 1.0, 1);
  static final Vector4 yellow = Vector4(1.0, 0.9, 0.25, 1);
}

bool debugDrawOn(World world) => world.resource<DebugSettings>().debugDraw;

/// `DebugDraw` only stages lines. Without a flush its buffers grow until
/// the engine's vertex limit trips, so one system owns the render side.
Feature installDebugDraw() {
  return (game) {
    game
      ..addSystem(
        Schedules.renderSync,
        flushDebugDraw,
        reads: const {},
        runIf: debugDrawOn,
      )
      ..addSystem(
        Schedules.renderSync,
        hideDebugDraw,
        reads: const {},
        runIf: not(debugDrawOn),
      );
  };
}

Node? _node;
Mesh? _mesh;

void flushDebugDraw(World world) {
  final geometry = DebugDraw.flushMesh();
  final scene = world.resources.tryGet<Scene>();
  if (scene == null) return;
  var node = _node;
  if (node == null) {
    // World space every frame, so culling bounds upkeep is wasted work.
    node = _node = Node(name: 'debug-draw')..frustumCulled = false;
    scene.root.add(node);
  }
  if (geometry == null) {
    node.visible = false;
    return;
  }
  final mesh = _mesh;
  if (mesh == null) {
    _mesh = Mesh(
      geometry,
      UnlitMaterial()
        ..baseColorFactor = Vector4(1, 1, 1, 1)
        ..alphaMode = AlphaMode.blend,
    )..primitives.first.castsShadow = false;
    node.mesh = _mesh;
  } else {
    mesh.primitives.first.geometry = geometry;
  }
  node.visible = true;
}

/// Drains anything a direct static caller staged and clears the last
/// frame the layer drew.
void hideDebugDraw(World world) {
  DebugDraw.clear();
  _node?.visible = false;
}
