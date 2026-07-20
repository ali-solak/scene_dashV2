library;

/// The run's whole-game mode. Every gameplay system gates on
/// `inState(fighting)`, so the other three ARE the pause — no separate
/// paused flag exists, and none should be added.
enum GameStatus {
  /// Before the run: the clearing is up and lit, the knight idles in it,
  /// and the camera holds a wide orbit. Nothing fights.
  title,

  fighting,
  lost,
  skillMenu,
}

final class RunControl {
  /// The first entry into `fighting` is a run start — whether that comes
  /// from the title screen or a restart.
  bool resetPending = true;
}

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
