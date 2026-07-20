/// The title screen, headless. Like the skill menu it is a [GameStatus]
/// rather than an overlay with a flag, so what these pin is the state
/// machine: nothing fights before START, pressing it starts a clean run,
/// and the opening camera push-in is armed exactly once.
library;

import 'package:combat_sample/enemies/enemies.dart';
import 'package:combat_sample/game/camera_rig.dart';
import 'package:combat_sample/game/game_state.dart';
import 'package:combat_sample/game/score.dart';
import 'package:combat_sample/waves/waves.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';

import 'support/fight_harness.dart';

void main() {
  test('the title screen fields nothing and runs no fight', () {
    final game = boot(initial: GameStatus.title);
    final world = game.world;

    game.pumpFixed(steps: 120); // two seconds of nothing happening

    expect(world.state<GameStatus>(), GameStatus.title);
    expect(
      world.entitiesWith(require: const [Enemy]).count(),
      0,
      reason: 'the wave director gates on fighting',
    );
    expect(world.resource<WaveState>().wave, 0);
  });

  test('the player still exists to be looked at', () {
    // The opening push-in has to have something to arrive at, so the
    // fighter is spawned (and, with a scene, bodied) before START.
    final game = boot(initial: GameStatus.title);
    final player = playerOf(game.world);
    expect(game.world.tryGet<Health>(player), isNotNull);
  });

  test('START begins a clean run and arms the push-in', () {
    final game = boot(initial: GameStatus.title);
    final world = game.world;
    // Points banked before the run must not survive into it.
    world.resource<Score>().award(500);

    game.emit(const GameStarted());
    game.pump();
    game.pump();

    expect(world.state<GameStatus>(), GameStatus.fighting);
    expect(world.resource<WaveState>().wave, 1, reason: 'the run started');
    expect(world.resource<Score>().points, 0, reason: 'startRun wiped it');
    expect(
      world.resource<CameraRig>().intro,
      greaterThan(0),
      reason: 'the camera flies in on the slow blend',
    );
  });

  test('START does nothing once the fight is already on', () {
    final game = boot();
    final world = game.world;
    game.pumpFixed(steps: 2);
    world.resource<Score>().award(70);

    game.emit(const GameStarted());
    game.pump();

    expect(world.state<GameStatus>(), GameStatus.fighting);
    expect(
      world.resource<Score>().points,
      70,
      reason: 'a stray start must not wipe a run in progress',
    );
  });
}
