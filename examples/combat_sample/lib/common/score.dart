/// The run's score: points earned by kills, spent on skills.
library;

/// Points banked this run. Kills award them (bigger enemies pay more);
/// the skill menu spends them. A plain resource: the HUD reads it
/// through a `WorldBuilder`, systems mutate it directly.
final class Score {
  /// Points available to spend.
  int points = 0;

  /// Total earned this run (the score proper; spending does not lower
  /// it, so the HUD can show a real score).
  int earned = 0;

  /// Kills this run.
  int kills = 0;

  void award(int value) {
    points += value;
    earned += value;
    kills++;
  }

  bool canAfford(int cost) => points >= cost;

  /// Spends [cost] if affordable; returns whether it went through.
  bool spend(int cost) {
    if (!canAfford(cost)) return false;
    points -= cost;
    return true;
  }

  void reset() {
    points = 0;
    earned = 0;
    kills = 0;
  }
}
