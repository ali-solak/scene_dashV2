/// A stable identifier for a single registered system.
///
/// System labels are used to declare ordering between systems via `before` and
/// `after` edges, and to detect duplicate registrations.
final class SystemLabel {
  /// The unique identifier string.
  final String id;

  const SystemLabel(this.id);

  @override
  bool operator ==(Object other) => other is SystemLabel && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'SystemLabel($id)';
}
