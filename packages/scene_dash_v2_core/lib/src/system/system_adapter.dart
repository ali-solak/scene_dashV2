import '../world/world.dart';

/// The runtime contract for an executable system.
///
/// Generated code (Phase 2) produces a [SystemAdapter] per `@System` class that
/// resolves the system's queries and resources once in [initialize] and then
/// calls the user `run()` method in [run]. During Phase 1 these adapters are
/// written by hand for tests.
///
/// If a hand-written adapter touches component data, also implement
/// `SystemAccessProvider` and declare what it reads and writes — otherwise the
/// startup access-conflict detector treats it as touching nothing and cannot
/// warn about unordered systems sharing its data.
abstract interface class SystemAdapter {
  /// Resolves queries, resources and event handles from [world]. Called once,
  /// after all plugins have registered and stores exist.
  void initialize(World world);

  /// Executes the system. Called once per schedule run; must be synchronous.
  void run();
}
