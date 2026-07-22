import '../system/system_access.dart';
import 'access_conflict.dart';
import 'schedule_label.dart';
import 'system_label.dart';
import 'system_registration.dart';
import 'system_set.dart';

/// Thrown when a schedule's system graph cannot be compiled.
final class ScheduleGraphError extends StateError {
  ScheduleGraphError(super.message);
}

/// The outcome of compiling a schedule: the execution order plus any detected
/// access conflicts between unordered systems.
final class ScheduleCompileResult {
  final List<SystemRegistration> ordered;
  final List<AccessConflict> conflicts;

  const ScheduleCompileResult(this.ordered, this.conflicts);
}

/// Compiles a set of [SystemRegistration]s into a deterministic execution
/// order via a stable topological sort over their `before`/`after` edges.
///
/// Reports, as [ScheduleGraphError]s:
///
/// * duplicate system labels;
/// * `before`/`after` references to unknown labels;
/// * dependency cycles.
///
/// When [detectConflicts] is true, it also computes ordering reachability and
/// returns [AccessConflict]s for pairs of systems that have no ordering between
/// them yet declare conflicting component access (write/write or read/write).
///
/// Ties are broken by registration order, so an unconstrained schedule runs its
/// systems in the order they were added.
abstract final class ScheduleGraph {
  static ScheduleCompileResult compile(
    ScheduleLabel scheduleLabel,
    List<SystemRegistration> registrations, {
    List<List<SystemSet>> setChains = const <List<SystemSet>>[],
    bool detectConflicts = true,
  }) {
    final byLabel = <SystemLabel, int>{};
    for (var i = 0; i < registrations.length; i++) {
      final label = registrations[i].label;
      if (byLabel.containsKey(label)) {
        throw ScheduleGraphError('Duplicate system label: ${label.id}');
      }
      byLabel[label] = i;
    }

    final count = registrations.length;
    final edges = List<List<int>>.generate(count, (_) => <int>[]);
    final inDegree = List<int>.filled(count, 0);

    void addEdge(int from, int to) {
      edges[from].add(to);
      inDegree[to]++;
    }

    int resolve(SystemLabel label, SystemLabel owner) {
      final index = byLabel[label];
      if (index == null) {
        throw ScheduleGraphError(
          'System ${owner.id} references unknown label ${label.id}.',
        );
      }
      return index;
    }

    for (var i = 0; i < count; i++) {
      final reg = registrations[i];
      for (final afterLabel in reg.after) {
        addEdge(resolve(afterLabel, reg.label), i);
      }
      for (final beforeLabel in reg.before) {
        addEdge(i, resolve(beforeLabel, reg.label));
      }
    }

    // Expand set chains into member-level edges: every member of an earlier
    // set runs before every member of a later one. An empty set is skipped
    // transparently — the non-empty sets around it still chain, so an empty
    // phase never breaks the ordering.
    if (setChains.isNotEmpty) {
      final members = <SystemSet, List<int>>{};
      for (var i = 0; i < count; i++) {
        final set = registrations[i].inSet;
        if (set != null) (members[set] ??= <int>[]).add(i);
      }
      for (final chain in setChains) {
        List<int>? previous;
        for (final set in chain) {
          final current = members[set];
          if (current == null || current.isEmpty) continue;
          if (previous != null) {
            for (final from in previous) {
              for (final to in current) {
                addEdge(from, to);
              }
            }
          }
          previous = current;
        }
      }
    }

    // Kahn's algorithm with a registration-order ready queue for determinism.
    final ready = <int>[];
    for (var i = 0; i < count; i++) {
      if (inDegree[i] == 0) ready.add(i);
    }

    final ordered = <SystemRegistration>[];
    while (ready.isNotEmpty) {
      // Take the smallest index so output is stable in registration order.
      var pick = 0;
      for (var k = 1; k < ready.length; k++) {
        if (ready[k] < ready[pick]) pick = k;
      }
      final node = ready.removeAt(pick);
      ordered.add(registrations[node]);
      for (final next in edges[node]) {
        if (--inDegree[next] == 0) ready.add(next);
      }
    }

    if (ordered.length != count) {
      final cyclic = <String>[
        for (var i = 0; i < count; i++)
          if (inDegree[i] > 0) registrations[i].label.id,
      ];
      throw ScheduleGraphError(
        'Dependency cycle among systems: ${cyclic.join(', ')}',
      );
    }

    final conflicts = detectConflicts
        ? _detectConflicts(scheduleLabel, registrations, edges)
        : const <AccessConflict>[];

    return ScheduleCompileResult(ordered, conflicts);
  }

  /// Finds write/write and read/write conflicts between systems that have no
  /// ordering relationship (neither reaches the other through the edges).
  static List<AccessConflict> _detectConflicts(
    ScheduleLabel scheduleLabel,
    List<SystemRegistration> registrations,
    List<List<int>> edges,
  ) {
    final count = registrations.length;

    // reachable[s][t] == true if there is a directed path s -> ... -> t.
    final reachable = List<List<bool>>.generate(
      count,
      (_) => List<bool>.filled(count, false),
    );
    for (var s = 0; s < count; s++) {
      final seen = reachable[s];
      final stack = <int>[...edges[s]];
      while (stack.isNotEmpty) {
        final n = stack.removeLast();
        if (seen[n]) continue;
        seen[n] = true;
        for (final m in edges[n]) {
          if (!seen[m]) stack.add(m);
        }
      }
    }

    SystemAccess accessOf(SystemRegistration reg) {
      final adapter = reg.adapter;
      if (adapter is SystemAccessProvider) {
        return (adapter as SystemAccessProvider).access;
      }
      return SystemAccess.empty;
    }

    final accesses = registrations.map(accessOf).toList(growable: false);

    final conflicts = <AccessConflict>[];
    for (var i = 0; i < count; i++) {
      for (var j = i + 1; j < count; j++) {
        final ordered = reachable[i][j] || reachable[j][i];
        if (ordered) continue;

        final ai = accesses[i];
        final aj = accesses[j];
        if (ai.reads.isEmpty &&
            ai.writes.isEmpty &&
            aj.reads.isEmpty &&
            aj.writes.isEmpty) {
          continue;
        }

        final labelA = registrations[i].label;
        final labelB = registrations[j].label;

        for (final component in ai.writes) {
          if (aj.writes.contains(component)) {
            conflicts.add(
              AccessConflict(
                schedule: scheduleLabel,
                a: labelA,
                b: labelB,
                component: component,
                kind: ConflictKind.writeWrite,
              ),
            );
          } else if (aj.reads.contains(component)) {
            conflicts.add(
              AccessConflict(
                schedule: scheduleLabel,
                a: labelA,
                b: labelB,
                component: component,
                kind: ConflictKind.readWrite,
              ),
            );
          }
        }
        for (final component in aj.writes) {
          // Only the read/write direction not already covered above.
          if (!ai.writes.contains(component) && ai.reads.contains(component)) {
            conflicts.add(
              AccessConflict(
                schedule: scheduleLabel,
                a: labelA,
                b: labelB,
                component: component,
                kind: ConflictKind.readWrite,
              ),
            );
          }
        }
      }
    }
    return conflicts;
  }
}
