/// The skill menu, headless. The menu is a [GameStatus], so these pin
/// the state machine. The trap: `OnEnter(fighting)` fires on boot and on
/// restart too, where it must wipe the run; closing the menu must not.
library;

import 'package:combat_sample/enemies/enemies.dart';
import 'package:combat_sample/game/game_state.dart';
import 'package:combat_sample/game/score.dart';
import 'package:combat_sample/skills/skills.dart';
import 'package:combat_sample/waves/waves.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';
import 'package:vector_math/vector_math.dart' show Vector3;

import 'support/fight_harness.dart';

void openMenu(TestGame game) {
  game.emit(const SkillMenuToggled());
  game.pump();
  expect(game.world.state<GameStatus>(), GameStatus.skillMenu);
}

void main() {
  test('the toggle opens and closes the menu', () {
    final game = boot();
    expect(game.world.state<GameStatus>(), GameStatus.fighting);

    openMenu(game);

    game.emit(const SkillMenuToggled());
    game.pump();
    expect(game.world.state<GameStatus>(), GameStatus.fighting);
  });

  test('the menu freezes the fight where it stands', () {
    final game = boot();
    final world = game.world;

    // Let the pack close in a little, then open the menu and hold.
    game.pumpFixed(steps: 40);
    openMenu(game);

    final positions = <Entity, Vector3>{};
    world.query<SceneTransform>(require: const [Enemy]).each((entity, t) {
      positions[entity] = t.translation.clone();
    });
    final wave = world.resource<WaveState>().wave;

    for (var i = 0; i < 60; i++) {
      game.pump();
    }

    world.query<SceneTransform>(require: const [Enemy]).each((entity, t) {
      expect(t.translation, positions[entity], reason: 'nobody moved');
    });
    expect(world.resource<WaveState>().wave, wave);
  });

  test('closing the menu RESUMES the run, it does not restart it', () {
    final game = boot();
    final world = game.world;
    final score = world.resource<Score>()..award(500);
    final health = world.get<Health>(playerOf(world))..current = 40;

    // Get the run somewhere recognisable: wave 2, points banked, hurt.
    world.entitiesWith(require: const [Enemy]).each(world.despawn);
    game.pumpFixed(steps: ticksFor(waveIntermissionSeconds) + 6);
    expect(world.resource<WaveState>().wave, 2);
    health.current = 40; // the wave heal just topped it up

    openMenu(game);
    game.emit(const SkillUpgradeRequested(Skill.fireGush));
    game.pump();

    game.emit(const SkillMenuToggled());
    game.pump();

    expect(world.state<GameStatus>(), GameStatus.fighting);
    expect(world.resource<WaveState>().wave, 2, reason: 'still wave 2');
    expect(health.current, 40, reason: 'not healed by a phantom restart');
    expect(score.earned, 500, reason: 'the score survived the pause');
    expect(
      world.resource<SkillBook>().isUnlocked(Skill.fireGush),
      isTrue,
      reason: 'what you bought in the menu is still bought',
    );
  });

  test('a skill bought in the menu is castable once the fight resumes', () {
    final game = boot();
    final world = game.world;
    world.resource<Score>().award(Skill.fireGush.cost);

    openMenu(game);
    game.emit(const SkillUpgradeRequested(Skill.fireGush));
    game.pump();

    game.emit(const SkillMenuToggled());
    game.pump();

    // Park a barbarian in the cone and fire.
    final enemy = dummyInFront(game, distance: 4);
    final full = world.get<Health>(enemy).current;

    game.emit(const SkillCast(Skill.fireGush));
    game.pumpFixed(steps: 3);

    expect(world.get<Health>(enemy).current, lessThan(full));
  });

  test('a cast dropped while the menu is open never fires', () {
    final game = boot();
    final world = game.world;
    world.resource<Score>().award(Skill.fireGush.cost);
    game.emit(const SkillUpgradeRequested(Skill.fireGush));
    game.pump();

    final enemy = dummyInFront(game, distance: 4);
    final full = world.get<Health>(enemy).current;

    openMenu(game);
    game.emit(const SkillCast(Skill.fireGush));
    for (var i = 0; i < 10; i++) {
      game.pump();
    }

    expect(world.get<Health>(enemy).current, full, reason: 'never fired');
    expect(
      world.resource<SkillBook>().isReady(Skill.fireGush),
      isTrue,
      reason: 'and it did not burn the cooldown either',
    );
  });

  test('the menu cannot be opened over the death screen', () {
    final game = boot();
    final world = game.world;
    world.get<Health>(playerOf(world)).current = 0;
    game.pump();
    game.pump();
    expect(world.state<GameStatus>(), GameStatus.lost);

    game.emit(const SkillMenuToggled());
    game.pump();
    expect(world.state<GameStatus>(), GameStatus.lost);
  });

  test('a restart still wipes the run, menu or no menu', () {
    final game = boot();
    final world = game.world;
    world.resource<Score>().award(500);

    // Open and close the menu first: the resume must not have consumed
    // the reset that a real restart is owed.
    openMenu(game);
    game.emit(const SkillMenuToggled());
    game.pump();

    world.get<Health>(playerOf(world)).current = 0;
    game.pump();
    game.pump();
    game.emit(const RestartRequested());
    game.pump();
    game.pump();

    expect(world.state<GameStatus>(), GameStatus.fighting);
    expect(world.resource<Score>().earned, 0, reason: 'a real reset');
    expect(world.resource<WaveState>().wave, 1);
  });
}
