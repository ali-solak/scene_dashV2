import '../world/world.dart';

/// Runs one system.
abstract interface class SystemAdapter {
  /// Resolves queries, resources and event handles from [world]. Called once,
  /// after all plugins have registered and stores exist.
  void initialize(World world);

  /// Executes the system. Called once per schedule run; must be synchronous.
  void run();
}
