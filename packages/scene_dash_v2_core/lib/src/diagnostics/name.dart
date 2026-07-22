/// A human-readable label for an entity: `Name('Boss')`, `Name('Checkpoint 3')`.
///
/// Plain data with no framework behavior — nothing looks entities up by name
/// and duplicates are fine. It exists so logs and failures can say *which*
/// entity: `World.debugDescribe` prints it when present, and bundles can
/// carry one so spawned entities identify themselves in diagnostics.
final class Name {
  /// The label rendered by debug tooling.
  final String value;

  const Name(this.value);
}
