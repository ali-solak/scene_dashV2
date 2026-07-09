/// Lose-condition tuning for the scene game example.
library;

// --- Lose conditions ---

/// Extra margin added to the central player body radius for the hit test.
const double hitPadding = 0.35;

/// Downward raycast length used to decide whether the player still has platform
/// below them. Falling is allowed until [playerFallLoseY] so the shove reads.
const double groundProbeDistance = 3;

/// Grace period after (re)spawn before fall detection runs, so dropping onto
/// the ramp at spawn is not mistaken for falling off, in seconds.
const double startupGrace = 0.6;
