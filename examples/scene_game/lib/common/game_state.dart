library;

import 'package:scene_dash_v2/scene_dash_v2.dart';

enum GameStatus { playing, lost }

enum GameAction { left, right, fire }

sealed class GameEvent {
  const GameEvent();
}

final class FirePressed extends GameEvent {
  const FirePressed();
}

final class FireReleased extends GameEvent {
  const FireReleased();
}

final class FireCanceled extends GameEvent {
  const FireCanceled();
}

final class RestartRequested extends GameEvent {
  const RestartRequested();
}

final class FpsCounter {
  double _windowSeconds = 0;
  int _windowFrames = 0;
  int _fps = 0;

  int get fps => _fps;

  void recordFrame(double deltaSeconds) {
    _windowSeconds += deltaSeconds;
    _windowFrames++;
    if (_windowSeconds >= 0.25) {
      _fps = (_windowFrames / _windowSeconds).round();
      _windowSeconds = 0;
      _windowFrames = 0;
    }
  }
}

final class GameState {
  final GameStopwatch _runClock = GameStopwatch();

  double get survived => _runClock.elapsed;

  String? lostReason;

  int get survivedTenths => (survived * 10).floor();

  void addSurvival(double delta) => _runClock.tick(delta);

  void recordLoss(String reason) => lostReason ??= reason;

  void reset() {
    _runClock.reset();
    lostReason = null;
  }
}
