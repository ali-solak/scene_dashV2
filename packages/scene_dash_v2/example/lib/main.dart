import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';
import 'package:vector_math/vector_math.dart' show Vector3;

Future<void> main() async {
  final game = await SceneGame.boot(features: [installCubes]);

  runApp(
    GameScope(
      // provides the game to the subtree
      game: game,
      child: MaterialApp(
        home: Scaffold(
          body: SceneView(
            // flutter_scene widget; not wrapped
            game.scene,
            cameraBuilder: _camera,
            onTick: game.onTick, // forwards frame ticks to the game
          ),
        ),
      ),
    ),
  );
}

Camera _camera(Duration elapsed) =>
    PerspectiveCamera(position: Vector3(0, 3, -6), target: Vector3.zero());

void installCubes(GameBuilder game) {
  // a feature: a plain function
  game
    ..addSystem(Schedules.startup, spawnCube, writes: {Orbit, SceneTransform})
    ..addSystem(Schedules.update, orbitCubes, writes: {Orbit, SceneTransform});
}

void spawnCube(World world) => world.spawn(cubeBundle());

void orbitCubes(World world) {
  // a system: a plain function
  world.query2<Orbit, SceneTransform>().each((entity, orbit, transform) {
    orbit.phase += orbit.speed * world.dt; // dt is schedule-aware
    transform
      ..x = orbit.radius * cos(orbit.phase)
      ..z = orbit.radius * sin(orbit.phase);
  });
}

final class Orbit {
  // a component: a plain class
  final double radius;
  final double speed;
  double phase;
  Orbit({required this.radius, required this.speed, this.phase = 0});
}

List<Object> cubeBundle() => [
  // a bundle: a function -> the spawn list
  Orbit(radius: 2, speed: 1),
  SceneTransform.zero(),
  NodeRef(Node(mesh: Mesh(CuboidGeometry(Vector3.all(0.8)), UnlitMaterial()))),
];
