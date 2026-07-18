import 'package:flutter_scene/scene.dart' show Node;
import 'package:flutter_test/flutter_test.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';
import 'package:scene_game/game/bounds.dart';
import 'package:scene_game/world/world.dart';
import 'package:vector_math/vector_math.dart' show Matrix4, Vector3;

/// The shared [DespawnOutside] sweep, headless, through the world feature:
/// one generic system serving any bundle that carries the part.
void main() {
  TestGame boot() {
    final game = TestGame.headless(
      strictAccess: true,
      features: [installWorldGeometry],
    );
    game.start();
    return game;
  }

  Node nodeAt(double x, double y, double z) =>
      Node(localTransform: Matrix4.translation(Vector3(x, y, z)));

  test('a carrier inside its region survives the sweep', () {
    final game = boot();
    final entity = game.world.spawn([
      SceneNode(nodeAt(0, 0, 0)),
      const DespawnOutside(minY: -1, maxZ: 3),
    ]);
    game.pump();
    expect(game.world.tryGet<SceneNode>(entity), isNotNull);
  });

  test('falling below minY despawns the carrier', () {
    final game = boot();
    final entity = game.world.spawn([
      SceneNode(nodeAt(0, -5, 0)),
      const DespawnOutside(minY: -1),
    ]);
    game.pump();
    expect(game.world.tryGet<SceneNode>(entity), isNull);
  });

  test('each plane is enforced independently', () {
    final game = boot();
    final pastZ = game.world.spawn([
      SceneNode(nodeAt(0, 0, 5)),
      const DespawnOutside(maxZ: 3),
    ]);
    final behindZ = game.world.spawn([
      SceneNode(nodeAt(0, 0, -8)),
      const DespawnOutside(minZ: -6),
    ]);
    final unbounded = game.world.spawn([
      SceneNode(nodeAt(0, -100, 100)),
      const DespawnOutside(),
    ]);
    game.pump();
    expect(game.world.tryGet<SceneNode>(pastZ), isNull);
    expect(game.world.tryGet<SceneNode>(behindZ), isNull);
    expect(game.world.tryGet<SceneNode>(unbounded), isNotNull);
  });
}
