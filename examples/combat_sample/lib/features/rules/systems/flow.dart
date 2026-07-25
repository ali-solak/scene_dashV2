part of '../rules.dart';

/// The run's shape: the title/restart/menu intents, the per-run clock
/// reset, and the death slow-motion.
void installRunFlow(GameBuilder game) {
  game
    ..addSystem(Schedules.frameStart, requestStart, reads: const {})
    ..addSystem(Schedules.frameStart, requestRestart, reads: const {})
    ..addSystem(Schedules.frameStart, toggleSkillMenu, reads: const {})
    ..addSystem(
      OnEnter(GameStatus.fighting),
      startRun,
      reads: const {},
      runIf: freshRun,
    )
    ..addSystem(OnEnter(GameStatus.lost), slowMotionOnLoss, reads: const {})
    ..addSystem(
      Schedules.update,
      checkPlayerDeath,
      reads: const {Player, Health},
      runIf: inState(GameStatus.fighting),
    );
}

/// Leaves the title screen (frameStart, alongside the other intents).
void requestStart(World world) {
  if (!world.consumeAny<GameStarted>()) return;
  if (world.state<GameStatus>() != GameStatus.title) return;
  world.resource<CameraRig>().intro = introZoomSeconds;
  world.setState(GameStatus.fighting);
}

/// Consumes the restart intent (frameStart, so it never lags the event
/// retention window): while lost, a restart request returns the world to
/// `fighting`, and `startRun` resets from there.
void requestRestart(World world) {
  if (!world.consumeAny<RestartRequested>()) return;
  if (world.state<GameStatus>() != GameStatus.lost) return;
  world.setState(GameStatus.fighting);
}

void toggleSkillMenu(World world) {
  if (!world.consumeAny<SkillMenuToggled>()) return;
  switch (world.state<GameStatus>()) {
    case GameStatus.fighting:
      world.setState(GameStatus.skillMenu);
    case GameStatus.skillMenu:
      world.setState(GameStatus.fighting);
    case GameStatus.lost:
    case GameStatus.title:
      break; // the death panel and the title screen own their screens
  }
}

/// `OnEnter(fighting)` on a fresh run ([freshRun]): undo the death
/// slow-motion. Every feature resets its own state through its own
/// `OnEnter(fighting)` system behind the same gate; the clock is the one
/// piece rules owns.
void startRun(World world) {
  world.clock.timeScale = 1;
}

/// Death drops the world into slow motion behind the restart prompt.
void slowMotionOnLoss(World world) {
  world.clock.timeScale = loseSlowMoTimeScale;
}

/// The player is dead when its health hits zero: drop the world into
/// `lost`. `OnEnter(lost)` slows time; the HUD shows the restart prompt.
void checkPlayerDeath(World world) {
  final health = world.query<Health>(require: const [Player]).firstOrNull?.$2;
  if (health != null && !health.alive) {
    world.setState(GameStatus.lost);
  }
}
