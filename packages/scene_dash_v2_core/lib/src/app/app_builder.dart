import 'dart:async';

import '../schedule/schedule_label.dart';
import '../schedule/system_descriptor.dart';
import '../schedule/system_label.dart';
import '../schedule/system_registration.dart';
import '../schedule/system_set.dart';
import '../system/system_adapter.dart';
import 'plugin.dart';

/// Registers app systems and data.
abstract interface class AppBuilder {
  /// Registers [descriptor] in [schedule].
  ///
  /// [runIf] can skip a run.
  /// [inSet] places the system in a [SystemSet].
  AppBuilder addSystem(
    SystemDescriptor descriptor, {
    required ScheduleLabel schedule,
    List<SystemDescriptor> after,
    List<SystemDescriptor> before,
    RunCondition? runIf,
    SystemSet? inSet,
  });

  /// Registers [adapter] in [schedule].
  ///
  /// [independentOf] skips conflict checks for the listed systems.
  AppBuilder addSystemAdapter(
    SystemAdapter adapter, {
    required ScheduleLabel schedule,
    required SystemLabel label,
    List<SystemLabel> after,
    List<SystemLabel> before,
    List<SystemLabel> independentOf,
    RunCondition? runIf,
    SystemSet? inSet,
  });

  /// Orders [sets] within [schedule].
  AppBuilder configureSets(ScheduleLabel schedule, List<SystemSet> sets);

  /// Registers state [S] with [initial].
  AppBuilder addState<S extends Object>(S initial);

  /// Registers an event channel for [T].
  ///
  /// [retainedUpdates] controls how long unread events remain.
  AppBuilder addEvent<T>({int? retainedUpdates});

  /// Inserts [resource].
  ///
  /// Throws when [T] already exists.
  AppBuilder insertResource<T extends Object>(T resource);

  /// Replaces or inserts [resource].
  AppBuilder replaceResource<T extends Object>(T resource);

  /// Registers cleanup to run once when the app shuts down.
  AppBuilder addCleanup(FutureOr<void> Function() cleanup);

  /// Builds [plugin] into this app if it has not already been added.
  AppBuilder addPlugin(Plugin plugin);
}

/// Adds systems as a group.
extension AppBuilderSystems on AppBuilder {
  /// Registers [descriptors] in [schedule].
  ///
  /// [chained] runs them in list order.
  AppBuilder addSystems(
    ScheduleLabel schedule,
    List<SystemDescriptor> descriptors, {
    RunCondition? runIf,
    SystemSet? inSet,
    bool chained = false,
  }) {
    for (var i = 0; i < descriptors.length; i++) {
      addSystem(
        descriptors[i],
        schedule: schedule,
        after: chained && i > 0
            ? <SystemDescriptor>[descriptors[i - 1]]
            : const <SystemDescriptor>[],
        runIf: runIf,
        inSet: inSet,
      );
    }
    return this;
  }
}
