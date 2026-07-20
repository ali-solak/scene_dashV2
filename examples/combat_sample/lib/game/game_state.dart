library;

enum GameStatus { fighting, lost, skillMenu }

final class RunControl {
  /// Boot is a run start.
  bool resetPending = true;
}

final class RestartRequested {
  const RestartRequested();
}

final class SkillMenuToggled {
  const SkillMenuToggled();
}
