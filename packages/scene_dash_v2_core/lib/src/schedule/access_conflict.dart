import 'schedule_label.dart';
import 'system_label.dart';

/// The kind of access hazard between two unordered systems.
enum ConflictKind {
  /// Both systems write the same component.
  writeWrite,

  /// One system writes a component the other reads.
  readWrite,
}

/// A detected access conflict between two systems in the same schedule that
/// have no ordering relationship and touch the same component in a conflicting
/// way.
final class AccessConflict {
  /// The schedule both systems belong to.
  final ScheduleLabel schedule;

  /// The two conflicting systems (order is not significant).
  final SystemLabel a;
  final SystemLabel b;

  /// The component both systems touch.
  final Type component;

  /// Whether this is a write/write or read/write hazard.
  final ConflictKind kind;

  const AccessConflict({
    required this.schedule,
    required this.a,
    required this.b,
    required this.component,
    required this.kind,
  });

  @override
  String toString() {
    final verb = kind == ConflictKind.writeWrite
        ? 'both write'
        : 'conflict (read/write) on';
    return 'Access conflict in schedule "${schedule.id}": ${a.id} and ${b.id} '
        '$verb $component without an ordering between them. Add an after/before '
        'edge, or confirm the access is safe.';
  }
}

/// How the app reacts to detected [AccessConflict]s during `start()`.
enum AccessConflictPolicy {
  /// Skip conflict detection entirely.
  ignore,

  /// Detect and collect conflicts, but do not throw. (Default.)
  warn,

  /// Detect conflicts and throw if any exist.
  error,
}
