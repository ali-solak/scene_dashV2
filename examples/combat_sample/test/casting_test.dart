import 'dart:math' as math;

import 'package:combat_sample/common/inputs.dart';
import 'package:combat_sample/features/player/player.dart';
import 'package:combat_sample/features/skills/skills.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';

import 'support/fight_harness.dart';

final class ShockwaveLog {
  int shockwaves = 0;
}

void recordShockwaves(World world) {
  world.resource<ShockwaveLog>().shockwaves += world.events<Shockwave>().length;
}

void installShockwaveLog(GameBuilder game) {
  game
    ..world.insert(ShockwaveLog())
    ..addSystem(Schedules.fixedUpdate, recordShockwaves, reads: const {});
}

void grant(TestGame game, Skill skill) {
  game.world.resource<SkillBook>().upgrade(skill);
}

Fighter fighterOf(TestGame game) =>
    game.world.get<Fighter>(playerOf(game.world));

void main() {
  test('a skill pressed mid-swing waits for the recovery, then casts', () {
    final game = boot();
    final fighter = fighterOf(game);
    grant(game, Skill.shield);
    game.world.buffer<CombatAction>().record(CombatAction.attack);
    game.pumpFixed(steps: ticksFor(startupSeconds) - 3);
    expect(fighter.phase.state, CombatPhase.startup);

    game.emit(const SkillCast(Skill.shield));
    game.pumpFixed(steps: 1);
    expect(fighter.phase.state, isNot(CombatPhase.casting));

    for (var i = 0; i < 40 && fighter.phase.state != CombatPhase.casting; i++) {
      game.pumpFixed(steps: 1);
    }
    expect(fighter.phase.state, CombatPhase.casting);
    expect(fighter.cast, Skill.shield);
  });

  test('a cast starts the tick it is pressed when the fighter is free', () {
    final game = boot();
    final fighter = fighterOf(game);
    grant(game, Skill.shield);
    game.emit(const SkillCast(Skill.shield));
    game.pumpFixed(steps: 1);
    expect(fighter.phase.state, CombatPhase.casting);
    expect(fighter.castReleased, isFalse);

    game.pumpFixed(steps: ticksFor(castMotionFor(Skill.shield).release));
    expect(fighter.castReleased, isTrue);
    expect(game.world.has<Barrier>(playerOf(game.world)), isTrue);
  });

  test('moving walks out of a cast once it has released', () {
    final game = boot();
    final fighter = fighterOf(game);
    grant(game, Skill.shield);
    cast(game, Skill.shield, settle: 0);
    game.world.axes<MoveAxis>().setValue(MoveAxis.y, 1);
    for (var i = 0; i < 30 && fighter.phase.state == CombatPhase.casting; i++) {
      game.pumpFixed(steps: 1);
    }
    final motion = castMotionFor(Skill.shield);
    expect(fighter.phase.state, CombatPhase.idle);
    expect(
      fighter.phase.elapsed,
      lessThan(motion.recovery),
      reason: 'left before the tail ran out',
    );
  });

  test('a cast turns toward an enemy before it releases', () {
    final game = boot();
    final world = game.world;
    grant(game, Skill.fireGush);
    final enemy = dummyInFront(game, distance: 3);
    final player = playerOf(world);
    final at = world.get<SceneTransform>(player).translation;
    final facing = world.get<PlayerMotion>(player).facing;
    final offAxis = facing - 0.7;
    world
        .get<SceneTransform>(enemy)
        .translation
        .setValues(
          at.x + math.sin(offAxis) * 3,
          0,
          at.z + math.cos(offAxis) * 3,
        );
    game.emit(const SkillCast(Skill.fireGush));
    pumpHolding(
      game,
      enemy,
      steps: ticksFor(castMotionFor(Skill.fireGush).release),
    );
    expect(
      (world.get<PlayerMotion>(player).facing - offAxis).abs(),
      lessThan(0.05),
    );
  });

  test('the finisher sends out one shockwave', () {
    final game = boot(extra: [installShockwaveLog]);
    final fighter = fighterOf(game);
    final buffer = game.world.buffer<CombatAction>();
    buffer.record(CombatAction.attack);
    game.pumpFixed(steps: 1);
    while (fighter.combo < 2) {
      if (fighter.phase.state == CombatPhase.recovery &&
          fighter.phase.elapsed >= comboLinkSeconds) {
        buffer.record(CombatAction.attack);
      }
      game.pumpFixed(steps: 1);
    }
    game.pumpFixed(steps: ticksFor(lightCombo[2].startup) + 2);
    expect(game.world.resource<ShockwaveLog>().shockwaves, 1);
  });
}
