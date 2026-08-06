part of '../rules.dart';

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

void requestStart(World world) {
  if (!world.consumeAny<GameStarted>()) return;
  if (world.state<GameStatus>() != GameStatus.title) return;
  world.resource<CameraRig>().intro = introZoomSeconds;
  world.setState(GameStatus.fighting);
}

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
      break;
  }
}

void startRun(World world) {
  world.clock.timeScale = 1;
}

void slowMotionOnLoss(World world) {
  world.clock.timeScale = loseSlowMoTimeScale;
}

void checkPlayerDeath(World world) {
  final health = world.query<Health>(require: const [Player]).firstOrNull?.$2;
  if (health != null && !health.alive) {
    world.setState(GameStatus.lost);
  }
}
