import 'package:basic_example_tower_defense/features/creeps/creeps.dart';
import 'package:basic_example_tower_defense/features/creeps/data/config.dart';
import 'package:basic_example_tower_defense/features/damage/damage.dart';
import 'package:basic_example_tower_defense/features/damage/data/config.dart';
import 'package:basic_example_tower_defense/features/rules/rules.dart';
import 'package:basic_example_tower_defense/features/towers/towers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';

void main() {
  TestGame boot() => TestGame.headless(
    features: [installDamage, installCreeps, installTowers, installRules],
  )..start();

  Entity creep(TestGame game) => game.world.spawn([
    const Creep(),
    Health(runnerHealth),
    SceneTransform(0, runnerRadius, 0),
  ]);

  test('a hit flashes, and the flash wears off on its own', () {
    final game = boot();
    final target = creep(game);
    game.pump();

    game.emit(DamageDealt(target, 1));
    game.pumpFixed(steps: 1);
    expect(game.world.has<HitFlash>(target), isTrue);

    game.pumpFixed(steps: (hitFlashSeconds * 60).ceil() + 1);
    expect(game.world.has<HitFlash>(target), isFalse);
  });

  test('a hurt creep shrinks toward its minimum size', () {
    final game = boot();
    final target = creep(game);
    game.pump();

    game.world.get<Health>(target).current = runnerHealth / 2;
    game.pump();

    final half = creepMinScale + (1 - creepMinScale) * 0.5;
    expect(game.world.get<SceneTransform>(target).scale.x, closeTo(half, 1e-6));
  });

  test('anything destroyed leaves a pop that cleans itself up', () {
    final game = boot();
    final target = creep(game);
    game.pump();

    game.emit(DamageDealt(target, runnerHealth));
    game.pump();
    expect(game.world.query<SceneTransform>().having<Pop>().count(), 1);

    game.pumpFixed(steps: (popSeconds * 60).ceil() + 2);
    expect(game.world.query<SceneTransform>().having<Pop>().isEmpty, isTrue);
  });
}
