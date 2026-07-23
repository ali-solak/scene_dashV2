/// A named system phase.
///
/// Systems join a set with `inSet:`. `configureSets` declares the phase order
/// for a schedule. Unconfigured sets do not impose ordering.
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
