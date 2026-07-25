part of '../rules.dart';

/// The run's shape: the title/restart/menu intents, the per-run clock
/// reset, the death slow-motion, and the wind that swells with the fight.
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
    )
    ..addSystem(Schedules.update, driveWind, reads: const {Enemy, Brawler});
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

/// Opens and closes the skill menu. The menu is just a state: everything
/// that fights gates on `fighting`, so the world stops the moment it
/// opens and resumes where it was on close. Ignored while lost; the
/// death panel owns that screen.
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

/// Wind dramaturgy: the strength eases toward a gust while the pack
/// circles and toward near-still while one telegraphs (the held breath
/// before a swing). Writes the resource the grass material reads, so
/// neither feature imports the other.
void driveWind(World world) {
  final wind = world.resource<WindState>();
  final dt = world.dt;
  var telegraphing = false;
  var anyLiving = false;
  world.query<Brawler>(require: const [Enemy]).each((entity, brawler) {
    if (brawler.phase.state == BrawlPhase.dying) return;
    anyLiving = true;
    if (brawler.phase.state == BrawlPhase.telegraph) telegraphing = true;
  });
  final target = !anyLiving
      ? 1.0
      : (telegraphing ? windCalmStrength : windGustStrength);
  wind.strength +=
      (target - wind.strength) * (1 - math.exp(-windEaseRate * dt));
}
