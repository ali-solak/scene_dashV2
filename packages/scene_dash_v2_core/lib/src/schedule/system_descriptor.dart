import '../system/system_adapter.dart';
import 'system_ref.dart';

/// Describes a schedulable system.
final class SystemDescriptor {
  /// This system's stable identity.
  final SystemRef ref;

  /// Builds a fresh adapter for this system. Called once when the descriptor is
  /// registered into a schedule.
  final SystemAdapter Function() buildAdapter;

  const SystemDescriptor(this.ref, this.buildAdapter);
}
