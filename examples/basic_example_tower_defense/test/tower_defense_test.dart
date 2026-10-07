import 'package:basic_example_tower_defense/common/game_state.dart';
import 'package:basic_example_tower_defense/features/arena/data/config.dart';
import 'package:basic_example_tower_defense/features/creeps/creeps.dart';
import 'package:basic_example_tower_defense/features/creeps/data/config.dart';
import 'package:basic_example_tower_defense/features/damage/damage.dart';
import 'package:basic_example_tower_defense/features/rules/data/config.dart';
import 'package:basic_example_tower_defense/features/rules/rules.dart';
import 'package:basic_example_tower_defense/features/towers/data/config.dart';
import 'package:basic_example_tower_defense/features/towers/towers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';
import 'package:vector_math/vector_math.dart' show Vector3;

void main() {
  TestGame boot() => TestGame.headless(
    features: [installDamage, installCreeps, installTowers, installRules],
  )..start();

  final buildSpot = Vector3(0, 0, 2);

  Entity creepAt(
    TestGame game,
    Vector3 at, {
    int next = 1,
    List<Object> extra = const [],
  }) => game.world.spawn([
    const Creep(),
    Health(runnerHealth),
    const Bounty(runnerBounty),
    PathProgress()..next = next,
    SceneTransform(at.x, runnerRadius, at.z),
    ...extra,
  ]);

  Entity towerAt(TestGame game, TowerKind kind, Vector3 at) => game.world.spawn(
    towerBundle(game.world, kind, Vector3(at.x, towerRadius, at.z)),
  );

  int towers(TestGame game) =>
      game.world.query<SceneTransform>().having<Tower>().count();

  test('a runner that reaches the core costs a life', () {
    final game = boot();
    final nearEnd = route[route.length - 2];
    creepAt(game, nearEnd, next: route.length - 1, extra: [Speed(creepSpeed)]);

    game.pumpFixed(steps: 120);

    expect(game.world.resource<Lives>().value, startingLives - 1);
  });

  test('the last life lost ends the run', () {
    final game = boot();
    for (var i = 0; i < startingLives; i++) {
      game.emit(const CreepReachedEnd());
    }

    game.pumpFixed(steps: 2);

    expect(game.world.state<GameStatus>(), GameStatus.lost);
  });

  test('a bolt tower kills a runner and the kill pays its bounty', () {
    final game = boot();
    creepAt(game, buildSpot + Vector3(2, 0, 0));
    towerAt(game, TowerKind.bolt, buildSpot);

    game.pumpFixed(steps: 120);

    expect(game.world.query<SceneTransform>().having<Creep>().isEmpty, isTrue);
    expect(game.world.resource<Gold>().value, startingGold + runnerBounty);
  });

  test('a pulse hits every creep around the tower at once', () {
    final game = boot();
    final a = creepAt(game, buildSpot + Vector3(1.5, 0, 0));
    final b = creepAt(game, buildSpot + Vector3(-1.5, 0, 0));
    towerAt(game, TowerKind.pulse, buildSpot);

    game.pumpFixed(steps: (pulseCooldownSeconds * 60).ceil() + 2);

    expect(game.world.get<Health>(a).current, runnerHealth - pulseDamage);
    expect(game.world.get<Health>(b).current, runnerHealth - pulseDamage);
  });

  test(
    'a shield tower shields its neighbours, and shields soak damage first',
    () {
      final game = boot();
      final bolt = towerAt(game, TowerKind.bolt, buildSpot);
      towerAt(game, TowerKind.shield, buildSpot + Vector3(2, 0, 0));
      game.pumpFixed(steps: 2);
      expect(game.world.has<Shield>(bolt), isTrue);

      game.emit(DamageDealt(bolt, 10));
      game.pumpFixed(steps: 1);

      expect(game.world.get<Health>(bolt).current, TowerKind.bolt.health);
      expect(game.world.get<Shield>(bolt).current, shieldStrength - 10);
    },
  );

  test('shields fade when their emitter is gone', () {
    final game = boot();
    final bolt = towerAt(game, TowerKind.bolt, buildSpot);
    final emitter = towerAt(
      game,
      TowerKind.shield,
      buildSpot + Vector3(2, 0, 0),
    );
    game.pumpFixed(steps: 2);

    game.world.despawn(emitter);
    game.pumpFixed(steps: 2);

    expect(game.world.has<Shield>(bolt), isFalse);
  });

  test('a raider leaves the road, bites a tower, and destroys it', () {
    final game = boot();
    towerAt(game, TowerKind.shield, buildSpot);
    creepAt(
      game,
      buildSpot + Vector3(3, 0, 0),
      extra: [Speed(raiderSpeed), Raider()],
    );

    game.pumpFixed(steps: 60 * 12);

    expect(towers(game), 0);
  });

  test('placement says why a spot is refused', () {
    final game = boot();
    final pond = decor.firstWhere((item) => item.kind == DecorKind.pond);
    Refusal? why(Vector3 at, [TowerKind kind = TowerKind.bolt]) =>
        whyNotPlace(game.world, kind, at);

    expect(why(route[10]), Refusal.road);
    expect(why(Vector3(pond.x, 0, pond.z)), Refusal.decor);
    expect(why(Vector3(30, 0, 0)), Refusal.edge);
    expect(why(buildSpot), isNull);

    placeTowerAt(game.world, TowerKind.bolt, buildSpot);
    game.pump();
    expect(why(buildSpot + Vector3(0.4, 0, 0)), Refusal.occupied);

    game.world.resource<Gold>().value = TowerKind.pulse.cost - 1;
    expect(why(Vector3(8, 0, 8), TowerKind.pulse), Refusal.gold);
  });

  test('towers keep placing after the first', () {
    final game = boot();
    final spots = [buildSpot, Vector3(8, 0, 8), Vector3(-8, 0, -10)];

    for (final spot in spots) {
      expect(whyNotPlace(game.world, TowerKind.bolt, spot), isNull);
      expect(placeTowerAt(game.world, TowerKind.bolt, spot), isTrue);
      game.pump();
    }

    expect(towers(game), spots.length);
    expect(
      game.world.resource<Gold>().value,
      startingGold - spots.length * TowerKind.bolt.cost,
    );
  });
}
