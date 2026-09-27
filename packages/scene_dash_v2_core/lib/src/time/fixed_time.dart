/// Fixed-step timing, updated each fixed update before the physics step.
///
/// A world resource: `world.resource<FixedTime>()`.
final class FixedTime {
  /// The fixed timestep, in seconds, used for the current step.
  double delta = 0;

  /// Number of fixed steps executed so far.
  int tick = 0;
}
