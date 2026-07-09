import 'package:flutter_test/flutter_test.dart';
import 'package:scene_game/game/physics_layers.dart';
import 'package:scene_game/rocks/rocks.dart';

/// Guards the rock physics-layer classification used by the lose-condition
/// system: it keeps `overlapSphere` hits whose collider carries
/// [PhysicsLayers.rock]. If a future change drops the layer on the rock
/// collider, rocks would silently stop being detected — this test fails first.
///
/// (Builds only the collider, not the rock's mesh, so it needs no GPU /
/// `Scene.initializeStaticResources`.)
void main() {
  test('a rock collider advertises the rock physics layer', () {
    final collider = buildRockCollider();
    expect(
      collider.collisionLayer & PhysicsLayers.rock,
      isNot(0),
      reason: 'rock collider must advertise the rock layer',
    );
  });

  test('the rock layer is distinct from player and platform', () {
    expect(PhysicsLayers.rock & PhysicsLayers.player, 0);
    expect(PhysicsLayers.rock & PhysicsLayers.platform, 0);
  });
}
