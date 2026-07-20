/// The game's state vocabulary and the run's discrete intents.
library;

/// The run's mode, registered with `game.addState`. Gameplay systems gate
/// on `inState(GameStatus.fighting)`, so entering [skillMenu] or [lost]
/// freezes the fight without any explicit pause plumbing.
enum GameStatus {
  /// The wave is running.
  fighting,

  /// The player died; the restart prompt is up.
  lost,

  /// The skill menu is open. Every gameplay system gates on [fighting],
  /// so this IS the pause — there is no separate paused flag to keep in
  /// step with anything.
  skillMenu,
}

/// Whether the next entry into [GameStatus.fighting] should wipe the run
/// and start over.
///
/// `OnEnter(fighting)` fires on boot, on a restart AND on closing the
/// skill menu — and only the first two are a new run. Without this the
/// menu would helpfully reset your score every time you closed it.
final class RunControl {
  /// Boot is a run start.
  bool resetPending = true;
}

/// The player asked to restart; honored only while lost.
final class RestartRequested {
  const RestartRequested();
}

/// Open/close the skill menu (honored while fighting / in the menu).
final class SkillMenuToggled {
  const SkillMenuToggled();
}
