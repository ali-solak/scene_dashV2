import 'system_label.dart';

/// Stable identity for a system.
final class SystemRef {
  /// The URI of the library that declares the system, e.g.
  /// `package:scene_game/player/player.dart`.
  final String library;

  /// The declared name of the system (class or function), e.g. `MovePlayerSystem`.
  final String name;

  /// Optional name for diagnostics.
  final String? debugName;

  const SystemRef(this.library, this.name, {this.debugName});

  /// Scheduling key for this identity.
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
