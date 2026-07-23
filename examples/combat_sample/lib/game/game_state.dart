library;

import 'package:scene_dash_v2/scene_dash_v2.dart';

/// The run's whole-game mode. Every gameplay system gates on
/// `inState(fighting)`, so the other three ARE the pause; no separate
/// paused flag exists, and none should be added.
enum GameStatus {
  /// Before the run: the clearing is up and lit, the knight idles in it,
  /// and the camera holds a wide orbit. Nothing fights.
  title,

  fighting,
  lost,
  skillMenu,
}

/// Run condition for `OnEnter(fighting)` work that belongs to a FRESH
/// run — boot, title start, restart — and not to a menu-close resume:
/// the transition's other side tells them apart. Every feature's reset
/// system gates on this, so "what counts as a new run" is defined once.
bool freshRun(World world) =>
    world.previousState<GameStatus>() != GameStatus.skillMenu;

/// Leaves the title screen and starts the run.
final class GameStarted {
  const GameStarted();
}

final class RestartRequested {
  const RestartRequested();
}

final class SkillMenuToggled {
  const SkillMenuToggled();
}
