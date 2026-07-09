import '../system/system_adapter.dart';
import 'system_ref.dart';

/// A schedulable system: its stable [SystemRef] identity plus how to build its
/// [SystemAdapter].
///
/// The generator emits one `SystemDescriptor` per `@System` (class or top-level
/// function) as a top-level value. Game code passes that descriptor to
/// `AppBuilder.addSystem` and references descriptors in `after`/`before` for
/// ordering — so a rename turns stale ordering references into compile errors,
/// and there is no hand-written label string and no `with _$…` mixin.
///
/// [buildAdapter] is invoked once, at registration (startup): it is not on the
/// per-frame path, so building the adapter there is free of hot-loop cost.
final class SystemDescriptor {
  /// This system's stable identity.
  final SystemRef ref;

  /// Builds a fresh adapter for this system. Called once when the descriptor is
  /// registered into a schedule.
  final SystemAdapter Function() buildAdapter;

  const SystemDescriptor(this.ref, this.buildAdapter);
}
