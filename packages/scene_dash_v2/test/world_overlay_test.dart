import 'package:flutter/widgets.dart';
import 'package:flutter_scene/scene.dart' show PerspectiveCamera;
import 'package:flutter_test/flutter_test.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';
import 'package:vector_math/vector_math.dart' show Vector3;

final class EnemyMarker implements Tag {}

/// A camera on the +Z axis looking at the origin projects the origin to
/// the exact viewport center.
PerspectiveCamera testCamera() =>
    PerspectiveCamera(position: Vector3(0, 0, 5), target: Vector3.zero());

void drive(WorldGame game, [int frames = 1]) {
  for (var i = 0; i < frames; i++) {
    game.onTick(Duration(milliseconds: 16 * (i + 1)), 1 / 60);
  }
}

void main() {
  testWidgets('WorldAnchor centers its child on the projected position, '
      'through the explicit camera parameter', (tester) async {
    final game = await WorldGame.boot();
    final entity = game.world.spawn([SceneTransform(0, 0, 0)]);
    drive(game);
    await tester.pumpWidget(
      GameScope(
        game: game,
        child: WorldOverlay(
          camera: testCamera(),
          children: [
            WorldAnchor(
              entity: entity,
              child: const SizedBox(width: 20, height: 10),
            ),
          ],
        ),
      ),
    );
    // Default test surface is 800x600; the origin projects to its center
    // and the child is centered on the point.
    expect(
      tester.getTopLeft(find.byType(SizedBox)),
      const Offset(400 - 10, 300 - 5),
    );
  });

  testWidgets('WorldAnchors adds and removes children as tagged entities '
      'spawn and despawn (store-revision-driven)', (tester) async {
    final game = await WorldGame.boot(
      features: [(game) => game.registerTag<EnemyMarker>()],
    );
    final a = game.world.spawn([EnemyMarker(), SceneTransform(0, 0, 0)]);
    game.world.spawn([EnemyMarker(), SceneTransform(1, 0, 0)]);
    drive(game);
    await tester.pumpWidget(
      GameScope(
        game: game,
        child: WorldOverlay(
          cameraBuilder: (_) => testCamera(),
          children: [
            WorldAnchors<EnemyMarker>(
              offsetY: 1,
              builder: (context, entity) =>
                  const SizedBox(width: 4, height: 4),
            ),
          ],
        ),
      ),
    );
    expect(find.byType(SizedBox), findsNWidgets(2));
    game.world.despawn(a);
    drive(game);
    await tester.pump();
    expect(find.byType(SizedBox), findsNWidgets(1));
  });

  testWidgets('a non-anchor child is rejected with guidance',
      (tester) async {
    final game = await WorldGame.boot();
    await tester.pumpWidget(
      GameScope(
        game: game,
        child: WorldOverlay(
          camera: testCamera(),
          children: const [Text('hud', textDirection: TextDirection.ltr)],
        ),
      ),
    );
    expect('${tester.takeException()}', contains('WorldAnchor'));
  });
}
