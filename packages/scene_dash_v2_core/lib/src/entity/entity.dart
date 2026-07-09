/// A lightweight, generational handle to an entity.
///
/// An entity is identified by a reusable [index] into the dense storage rows
/// and a [generation] counter. When an entity is despawned its index becomes
/// available for reuse, and the generation is bumped, so a stale [Entity] value
/// that still points at the old generation can be detected and rejected rather
/// than silently addressing a different, newer entity that reused the index.
final class Entity {
  /// The reusable slot index this entity occupies.
  final int index;

  /// The generation stamp that disambiguates index reuse.
  final int generation;

  /// Creates an entity handle. Game code should obtain entities from
  /// [Commands] or the world rather than constructing them directly.
  const Entity(this.index, this.generation);

  /// A sentinel value representing "no entity".
  static const Entity invalid = Entity(0xFFFFFFFF, 0);

  bool get isValid => index != invalid.index;

  @override
  bool operator ==(Object other) =>
      other is Entity && other.index == index && other.generation == generation;

  @override
  int get hashCode => Object.hash(index, generation);

  @override
  String toString() => 'Entity($index v$generation)';
}
