/// The shared headless fight: the same feature cascade `main` boots,
/// minus the assets. Every combat suite starts here so there is one
/// definition of "the fight" to keep in step with the composition root.
library;

import 'dart:math' as math;

import 'package:combat_sample/game/camera_rig.dart';
import 'package:combat_sample/game/game_state.dart';
import 'package:combat_sample/game/inputs.dart';
import 'package:combat_sample/game/sets.dart';
import 'package:combat_sample/enemies/enemies.dart';
import 'package:combat_sample/player/player.dart';
import 'package:combat_sample/rules/rules.dart';
import 'package:combat_sample/skills/skills.dart';
import 'package:combat_sample/waves/waves.dart';
import 'package:combat_sample/world/data/assets.dart';
import 'package:combat_sample/world/world.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';

int ticksFor(double seconds) {
  var t = 0.0;
  var n = 0;
  while (t < seconds) {
    t += combatFixedDt;
    n++;
  }
  return n;
}

/// Boots the same cascade `main` does, minus the assets.
///
/// Defaults to [GameStatus.fighting] rather than to `main`'s title
/// screen: almost every suite here is about the fight, and making each
/// one press START first would be ceremony. Pass [initial] to exercise
/// the shell instead.
TestGame boot({GameStatus initial = GameStatus.fighting}) {
  final game = TestGame.headless(
    fixedDt: combatFixedDt,
    strictAccess: true,
    features: [
      (game) {
        game
          ..addState<GameStatus>(initial)
          ..configureSets(Schedules.fixedUpdate, [
            GameSets.movement,
            GameSets.enemyMovement,
            GameSets.actions,
            GameSets.resolution,
            GameSets.waves,
          ])
          ..configureSets(Schedules.update, [GameSets.logic])
          ..world.insert(ButtonInput<CombatAction>())
          ..world.insert(AxisInput<MoveAxis>())
          ..world.insert(InputBuffer<CombatAction>(window: bufferWindow))
          ..world.insert(LookInput())
          ..world.insert(CameraRig());
      },
      installWorld(WorldAssets.none()),
      installPlayer,
      installEnemies,
      installWaves,
      installSkills,
      installRules,
    ],
  );
  game.start();
  game.pumpFixed(steps: 1); // event readers register lazily
  return game;
}

Entity playerOf(World world) =>
    world.entitiesWith(require: const [Player]).firstOrNull!;

/// Winds up a strike and plants [enemy] right in front of the player just
/// before the active edge, so exactly that swing connects.
void landPlayerStrike(TestGame game, Entity enemy, {bool heavy = false}) {
  final world = game.world;
  final player = playerOf(world);
  final playerTransform = world.get<SceneTransform>(player);
  final facing = world.get<PlayerMotion>(player).facing;
  final windup = heavy ? heavyStartupSeconds : startupSeconds;

  if (heavy) {
    world.buttons<CombatAction>().setPressed(CombatAction.attack, true);
  }
  world.buffer<CombatAction>().record(CombatAction.attack);
  game.pumpFixed(steps: 1); // startup entered
  game.pumpFixed(steps: ticksFor(windup) - 2);

  final enemyTransform = world.get<SceneTransform>(enemy);
  enemyTransform.translation.setValues(
    playerTransform.translation.x + math.sin(facing) * 1.2,
    0,
    playerTransform.translation.z + math.cos(facing) * 1.2,
  );
  game.pumpFixed(steps: 3); // crosses the active edge
  if (heavy) {
    world.buttons<CombatAction>().setPressed(CombatAction.attack, false);
  }
}

/// Clears the field and drops one barbarian [distance] straight in front
/// of the player, at full health. Returns it.
Entity dummyInFront(TestGame game, {double distance = 3}) {
  final world = game.world;
  world.entitiesWith(require: const [Enemy]).each(world.despawn);
  game.pumpFixed(steps: 1);

  final player = playerOf(world);
  final at = world.get<SceneTransform>(player).translation;
  final facing = world.get<PlayerMotion>(player).facing;
  world.spawn(
    enemyBundle(
      at.x + math.sin(facing) * distance,
      at.z + math.cos(facing) * distance,
      index: 0,
    ),
  );
  game.pumpFixed(steps: 1);
  return world.entitiesWith(require: const [Enemy]).firstOrNull!;
}

/// Pumps [steps] fixed steps while pinning [enemy] where it stands.
/// Barbarians walk toward the player, so any test that waits on a
/// position-sensitive effect has to hold its dummy still or it is really
/// testing the pathing.
void pumpHolding(TestGame game, Entity enemy, {required int steps}) {
  final spot = game.world.get<SceneTransform>(enemy).translation.clone();
  for (var i = 0; i < steps; i++) {
    game.world.get<SceneTransform>(enemy).translation.setFrom(spot);
    game.pumpFixed(steps: 1);
  }
}
