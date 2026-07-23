/// Combat input outside the fight must be inert: the widget gate stops
/// new intents on the title/menu/death screens, and `OnExit(fighting)`
/// wipes what was already banked — a press made on the way out (inside
/// the 0.75 s wall-clock window) must never fire on the way back in.
library;

import 'package:combat_sample/enemies/enemies.dart';
import 'package:combat_sample/game/camera_rig.dart';
import 'package:combat_sample/game/controls.dart';
import 'package:combat_sample/game/game_state.dart';
import 'package:combat_sample/game/inputs.dart';
import 'package:combat_sample/game/sets.dart';
import 'package:combat_sample/player/player.dart';
import 'package:combat_sample/rules/rules.dart';
import 'package:combat_sample/skills/skills.dart';
import 'package:combat_sample/waves/waves.dart';
import 'package:combat_sample/world/data/assets.dart';
import 'package:combat_sample/world/world.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';

import 'support/fight_harness.dart';

void main() {
  test('leaving the fight clears buffered intents (menu)', () {
    final game = boot();
    final world = game.world;

    // Banked mid-fight, then the menu opens within the press window.
    world.buffer<CombatAction>().record(CombatAction.roll);
    game.emit(const SkillMenuToggled());
    game.pump();
    expect(world.state<GameStatus>(), GameStatus.skillMenu);

    game.emit(const SkillMenuToggled());
    game.pump();
    expect(world.state<GameStatus>(), GameStatus.fighting);
    expect(
      world.buffer<CombatAction>().consume(CombatAction.roll),
      isFalse,
      reason: 'the roll banked before the menu must not fire on resume',
    );
  });

  test('leaving the fight clears buffered intents (death)', () {
    final game = boot();
    final world = game.world;

    world.buffer<CombatAction>().record(CombatAction.attack);
    world.setState(GameStatus.lost);
    game.pump();
    expect(world.state<GameStatus>(), GameStatus.lost);
    expect(
      world.buffer<CombatAction>().has(CombatAction.attack),
      isFalse,
      reason: 'OnExit(fighting) wipes intents on the way down too',
    );
  });

  testWidgets('the controls bank no combat intents outside fighting', (
    tester,
  ) async {
    final game = await WorldGame.boot(
      features: [
        (game) {
          game
            ..addState<GameStatus>(GameStatus.title)
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
    void drive([int frames = 1]) {
      for (var i = 0; i < frames; i++) {
        game.onTick(Duration(milliseconds: 16 * (i + 1)), 1 / 60);
      }
    }

    drive();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: GameScope(
          game: game,
          child: const GameControls(scene: SizedBox(), hud: SizedBox()),
        ),
      ),
    );

    // On the title screen: roll and attack presses bank nothing.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyJ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyJ);
    final buffer = game.world.buffer<CombatAction>();
    expect(buffer.has(CombatAction.roll), isFalse);
    expect(buffer.has(CombatAction.attack), isFalse);

    // Start the fight; the same keys now land.
    game.emit(const GameStarted());
    drive(3);
    expect(game.world.state<GameStatus>(), GameStatus.fighting);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
    expect(buffer.has(CombatAction.roll), isTrue);

    await game.shutdown();
  });
}
