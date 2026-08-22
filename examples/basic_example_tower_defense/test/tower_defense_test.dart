import 'package:basic_example_tower_defense/features/arena/data/config.dart';
import 'package:basic_example_tower_defense/features/creeps/creeps.dart';
import 'package:basic_example_tower_defense/features/creeps/data/config.dart';
import 'package:basic_example_tower_defense/features/rules/rules.dart';
import 'package:basic_example_tower_defense/features/rules/data/config.dart';
import 'package:basic_example_tower_defense/features/towers/data/config.dart';
import 'package:basic_example_tower_defense/features/towers/towers.dart';
import 'package:basic_example_tower_defense/common/game_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';
import 'package:vector_math/vector_math.dart' show Vector3;

void main() {
  TestGame boot() =>
      TestGame.headless(features: [installCreeps, installTowers, installRules])
        ..start();

  Entity spawnCreepAt(TestGame game, Vector3 at, {int waypoint = 1}) =>
      game.world.spawn([
        const Creep(),
        Health(10),
        PathProgress()..next = waypoint,
        SceneTransform(at.x, creepRadius, at.z),
      ]);

  test('a creep that walks off the end of the path costs a life', () {
    final game = boot();
    spawnCreepAt(
      game,
      towerPath[towerPath.length - 2],
      waypoint: towerPath.length - 1,
    );

    game.pumpFixed(steps: 400);

    expect(game.world.resource<Lives>().value, startingLives - 1);
  });

  test('the last life lost ends the run', () {
    final game = boot();
    for (var i = 0; i < startingLives; i++) {
      game.emit(const CreepReachedEnd());
    }

    game.pumpFixed(steps: 2);

    expect(game.world.resource<Lives>().value, 0);
    expect(game.world.state<GameStatus>(), GameStatus.lost);
  });

  test('a tower in range kills a creep, and the kill pays gold', () {
    final game = boot();
    final start = towerPath.first;
    spawnCreepAt(game, start);
    game.world.spawn([Tower(), SceneTransform(start.x + 2, towerRadius, -6)]);

    game.pumpFixed(steps: 60);

    expect(game.world.query<Health>(require: const [Creep]).count(), 0);
    expect(game.world.resource<Gold>().value, startingGold + creepBounty);
  });

  test('a tower out of range never fires', () {
    final game = boot();
    spawnCreepAt(game, towerPath.first);
    game.world.spawn([Tower(), SceneTransform(14, towerRadius, 14)]);

    game.pumpFixed(steps: 60);

    final (_, health) = game.world.query<Health>(require: const [Creep]).single;
    expect(health.current, 10);
  });

  test('placement is refused on the creeps lane', () {
    final game = boot();
    final onLane = towerPath.first;
    placeTowerAt(game.world, Vector3(onLane.x + 4, 0, onLane.z));

    expect(game.world.query<Tower>().isEmpty, isTrue);
    expect(game.world.resource<Gold>().value, startingGold);
  });

  test('a second tower cannot stack on the first', () {
    final game = boot();
    placeTowerAt(game.world, Vector3(0, 0, -2));
    placeTowerAt(game.world, Vector3(0.4, 0, -2));

    expect(game.world.query<Tower>().count(), 1);
    expect(game.world.resource<Gold>().value, startingGold - towerCost);
  });

  test('placement is refused when gold is short', () {
    final game = boot();
    game.world.resource<Gold>().value = towerCost - 1;
    placeTowerAt(game.world, Vector3.zero());

    expect(game.world.query<Tower>().isEmpty, isTrue);
    expect(game.world.resource<Gold>().value, towerCost - 1);
  });
}
