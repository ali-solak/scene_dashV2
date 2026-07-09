import 'package:flutter_test/flutter_test.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';
import 'package:scene_game/game/game_state.dart';

/// Pure-logic coverage for the run's data and its `GameStatus` state machine —
/// no scene or GPU.
void main() {
  test('a fresh game has a clean timer and no loss reason', () {
    final game = GameState();
    expect(game.survived, 0);
    expect(game.lostReason, isNull);
  });

  test('survival accumulates and reports tenths', () {
    final game = GameState()
      ..addSurvival(1.24)
      ..addSurvival(0.30);
    expect(game.survived, closeTo(1.54, 1e-9));
    expect(game.survivedTenths, 15);
  });

  test('the first recorded loss reason wins', () {
    final game = GameState()..recordLoss('You fell off the platform');
    expect(game.lostReason, 'You fell off the platform');

    game.recordLoss('A later loss reason');
    expect(
      game.lostReason,
      'You fell off the platform',
      reason: 'first loss wins',
    );
  });

  test('reset returns the game to clean run data', () {
    final game = GameState()
      ..addSurvival(5)
      ..recordLoss('You fell off the platform')
      ..reset();
    expect(game.survived, 0);
    expect(game.lostReason, isNull);
  });

  test('the GameStatus machine starts playing and transitions to lost', () {
    final game = TestGame.headless(features: [
      (g) => g.addState<GameStatus>(GameStatus.playing),
    ]);
    game.pump();
    expect(game.world.state<GameStatus>(), GameStatus.playing);

    game.world.setState(GameStatus.lost);
    game.pump();

    final status = game.world.resource<CurrentState<GameStatus>>();
    expect(status.value, GameStatus.lost);
    expect(status.previous, GameStatus.playing);
  });
}
