library;

import 'package:scene_dash_v2/scene_dash_v2.dart';

/// The game's current mode.
enum GameStatus { title, fighting, lost, skillMenu }

/// Whether entering combat starts a new run.
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
