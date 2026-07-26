/// Plain gameplay vocabulary shared between systems and the Flutter HUD.
library;

import 'package:scene_dash_v2/scene_dash_v2.dart';

/// The run's mode, registered as a state machine (`game.addState`).
/// Gameplay systems gate on `inState(GameStatus.playing)`; transitions are
/// requested through `world.setState`.
enum GameStatus { playing, lost }

/// The held input actions; widgets and key handlers write
/// `world.buttons<GameAction>()`, systems read it.
enum GameAction { left, right, fire }

/// Discrete input intents, sent with `world.emit` and read with
/// `world.events` — delivered exactly once, never leaked across the
/// fixed-step loop.
sealed class GameEvent {
  const GameEvent();
}

/// Fire pressed — the blaster begins charging or starts a burst.
final class FirePressed extends GameEvent {
  const FirePressed();
}

/// Fire released — the blaster commits a burst or charged shot.
final class FireReleased extends GameEvent {
  const FireReleased();
}

/// Fire aborted (focus loss, disposal, `onTapCancel`): charging stops
/// without firing.
final class FireCanceled extends GameEvent {
  const FireCanceled();
}

/// The player asked to restart; honoured only while lost.
final class RestartRequested extends GameEvent {
  const RestartRequested();
}

/// Frame-rate counter, fed by the render tick in `main()` and read by the
/// HUD snapshot. A plain resource: it carries no notification — the HUD's
/// `WorldBuilder` re-selects every rendered frame anyway.
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

/// Run data (timer, loss reason). The playing/lost mode itself lives in
/// the `GameStatus` state machine, not here.
final class GameState {
  final GameStopwatch _runClock = GameStopwatch();

  /// Seconds survived this run.
  double get survived => _runClock.elapsed;

  String? lostReason;

  int get survivedTenths => (survived * 10).floor();

  void addSurvival(double delta) => _runClock.tick(delta);

  /// Records why the run ended; the first recorded reason wins.
  void recordLoss(String reason) => lostReason ??= reason;

  void reset() {
    _runClock.reset();
    lostReason = null;
  }
}
