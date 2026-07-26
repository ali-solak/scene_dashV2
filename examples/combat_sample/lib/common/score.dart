/// The run's score: points earned by kills, spent on skills.
library;

/// Score for the current run.
final class Score {
  /// Points available to spend.
  int points = 0;

  /// Total points earned this run.
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
