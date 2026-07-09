import 'system_label.dart';

/// A stable, collision-free identity for a registered system.
///
/// Identity is the pair (defining library URI, declared name) — *not* a
/// hand-written string and *not* `runtimeType`. Two libraries can each declare a
/// `void update(...)` system or a `class Update`; deriving identity from the
/// library URI keeps those distinct, and a generated [SystemRef] const means a
/// rename turns stale ordering references into compile errors instead of
/// silently-broken strings.
///
/// The generator emits one `SystemRef` per `@System`. Game code references those
/// generated consts for ordering (`after:`/`before:`); it does not construct
/// `SystemRef`s by hand.
final class SystemRef {
  /// The URI of the library that declares the system, e.g.
  /// `package:scene_game/player/player.dart`.
  final String library;

  /// The declared name of the system (class or function), e.g. `MovePlayerSystem`.
  final String name;

  /// An optional human-friendly alias for diagnostics only. Never part of
  /// identity — equality and hashing use [library] + [name].
  final String? debugName;

  const SystemRef(this.library, this.name, {this.debugName});

  /// The internal scheduling key derived from this identity. The schedule graph
  /// keys systems by [SystemLabel]; encoding `library#name` keeps two systems
  /// with the same declared name in different libraries distinct. Game code never
  /// builds this by hand — it passes the generated descriptor to `addSystem` and
  /// references descriptors in `after`/`before`.
  SystemLabel get label => SystemLabel('$library#$name');

  @override
  bool operator ==(Object other) =>
      other is SystemRef && other.library == library && other.name == name;

  @override
  int get hashCode => Object.hash(library, name);

  @override
  String toString() =>
      debugName != null ? 'SystemRef($debugName: $name)' : 'SystemRef($name)';
}
