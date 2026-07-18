import 'package:flutter_scene/scene.dart' show Node;
import 'package:flutter_test/flutter_test.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';
import 'package:scene_game/collectables/collectables.dart';
import 'package:scene_game/collectables/data/config.dart';
import 'package:scene_game/game/game_state.dart';
import 'package:scene_game/game/sets.dart';
import 'package:scene_game/player/player.dart' show Player;

/// Headless behavior of the pickup spawner. The cadence itself is the
/// registration's `every(shieldPickupInterval)` (timing covered by the
/// core run-condition tests); what the game owns — and what runs here —
/// is the scene gate: the bundle builds GPU meshes, so a headless boot
/// must skip the spawn system entirely instead of crashing.
void main() {
  const dt = 1 / 60;
  final intervalSteps = (shieldPickupInterval / dt).ceil();

  TestGame boot() {
    final game = TestGame.headless(
      strictAccess: true,
      features: [
        (g) {
          g.addState<GameStatus>(GameStatus.playing);
          g.configureSets(Schedules.update, [GameSets.logic, GameSets.rules]);
          g.registerTag<Player>();
        },
        installCollectables,
      ],
    );
    game.start();
    game.world.spawn([const Player(), SceneNode(Node())]);
    game.pump();
    return game;
  }

  test('headless boots skip the scene-gated spawner past the interval', () {
    final game = boot();
    game.pumpFixed(steps: intervalSteps * 2);
    expect(
      game.world.entitiesWith(require: const [ShieldPickup]).count(),
      0,
      reason: 'no Scene resource — the spawn system never runs',
    );
  });

  test('lanes stay within the spawn band', () {
    final lanes = PickupLanes(seed: 7);
    for (var i = 0; i < 50; i++) {
      expect(
        lanes.nextLane().abs(),
        lessThanOrEqualTo(shieldPickupSpawnHalfWidth),
      );
    }
  });
}
