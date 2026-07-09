/// A named group of systems, used to order features against each other
/// without referencing each other's systems.
///
/// A system joins a set at registration (`addSystem(..., inSet: ...)`); the
/// app declares the order of the sets once per schedule with
/// `configureSets`. That keeps cross-feature ordering at the app level:
/// a plugin only names its own phase, and never imports another feature's
/// system descriptors just to write an `after:` edge.
///
/// ```dart
/// abstract final class GameSets {
///   static const logic = SystemSet('game.logic');
///   static const reactions = SystemSet('game.reactions');
/// }
///
/// app
///   ..configureSets(Schedules.update, [GameSets.logic, GameSets.reactions])
///   ..addSystem(updateShieldStateSystem,
///       schedule: Schedules.update, inSet: GameSets.logic)
///   ..addSystem(evaluateGameRulesSystem,
///       schedule: Schedules.update, inSet: GameSets.reactions);
/// ```
///
/// Set order compiles down to ordinary `after` edges between the members at
/// schedule compile time, so it composes with per-system `before`/`after`
/// and participates in the same cycle detection. Membership in a set that
/// is never configured is inert; a configured set with no members is
/// skipped transparently (the sets around it still order against each
/// other, so an empty phase never breaks the chain).
final class SystemSet {
  /// The unique identifier string.
  final String id;

  const SystemSet(this.id);

  @override
  bool operator ==(Object other) => other is SystemSet && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'SystemSet($id)';
}
