import 'dart:async';

import '../schedule/schedule_label.dart';
import '../schedule/system_descriptor.dart';
import '../schedule/system_label.dart';
import '../schedule/system_registration.dart';
import '../schedule/system_set.dart';
import '../system/system_adapter.dart';
import 'plugin.dart';

/// The registration surface handed to a [Plugin.build].
///
/// A plugin uses the builder to register systems, declare event channels,
/// insert resources and pull in dependency plugins. It deliberately does *not*
/// expose frame execution — that belongs to the app/scene driver.
abstract interface class AppBuilder {
  /// Registers a `@System` [descriptor] into [schedule], optionally constrained
  /// to run `after`/`before` other systems (referenced by their descriptors).
  ///
  /// [descriptor] is the generated `SystemDescriptor` for a `@System` class or
  /// function (e.g. `movePlayerSystem`); its identity and adapter come from the
  /// generator, so there is no hand-written label and no `with _$…` mixin.
  ///
  /// [runIf] gates each run: the condition is evaluated every schedule pass
  /// and the system is skipped while it returns `false`.
  ///
  /// [inSet] places the system in a [SystemSet]; set order is declared per
  /// schedule with [configureSets], so features order against each other's
  /// *phases* without referencing each other's systems.
  AppBuilder addSystem(
    SystemDescriptor descriptor, {
    required ScheduleLabel schedule,
    List<SystemDescriptor> after,
    List<SystemDescriptor> before,
    RunCondition? runIf,
    SystemSet? inSet,
  });

  /// Registers a system [adapter] directly. Used by hand-written adapters
  /// (tests, advanced integrations) that do not go through a `@System` class.
  ///
  /// [independentOf] exempts this system's access-conflict pairing with the
  /// listed labels — an author assertion of independence, symmetric, with
  /// no effect on ordering.
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

  /// Declares that, within [schedule], the members of each set in [sets] run
  /// before the members of every later set in the list. See [SystemSet].
  ///
  /// May be called multiple times (chains accumulate) and before or after
  /// the member systems register; everything resolves at schedule compile.
  AppBuilder configureSets(ScheduleLabel schedule, List<SystemSet> sets);

  /// Registers a state machine for [S] (normally an enum), starting at
  /// [initial].
  ///
  /// Inserts a `CurrentState<S>` and a `NextState<S>` resource. Systems queue
  /// transitions through `NextState<S>.set(...)`; the app applies them at
  /// `App.applyStateTransitions()`, running the `OnExit`/`OnEnter` schedules
  /// of the values involved. `OnEnter(initial)` runs once during `App.start()`,
  /// after the startup schedule. Gate steady-state systems with
  /// `runIf: inState(...)`.
  AppBuilder addState<S extends Object>(S initial);

  /// Declares an event channel for event type [T] (idempotent).
  ///
  /// [retainedUpdates] bounds how many event-maintenance passes (normally one
  /// per frame) an unread event survives, so a reader that stops draining
  /// cannot grow the buffer without bound. The default of `8` keeps an event
  /// readable for the frame it was sent plus seven more — wide enough that
  /// fixed-step and briefly-gated readers on high-refresh displays never
  /// silently lose an edge; pass `null` to retain events until every reader
  /// has consumed them.
  AppBuilder addEvent<T>({int? retainedUpdates});

  /// Inserts the resource instance for type [T].
  ///
  /// Throws [StateError] if a resource of type [T] is already present: each
  /// resource should be owned by exactly one place (the plugin that uses it, or
  /// a single insertion through the game for an externally-constructed
  /// dependency). Use [replaceResource] when swapping is intentional, so an
  /// accidental double-registration fails loudly instead of silently winning.
  AppBuilder insertResource<T extends Object>(T resource);

  /// Replaces (or inserts) the resource instance for type [T]. Use this when
  /// intentionally swapping a resource; [insertResource] rejects duplicates.
  AppBuilder replaceResource<T extends Object>(T resource);

  /// Registers cleanup to run once when the app shuts down.
  AppBuilder addCleanup(FutureOr<void> Function() cleanup);

  /// Builds [plugin] into this app if it has not already been added.
  AppBuilder addPlugin(Plugin plugin);
}

/// Batch registration sugar over [AppBuilder.addSystem].
extension AppBuilderSystems on AppBuilder {
  /// Registers every descriptor in [descriptors] into [schedule], sharing one
  /// [runIf] — the shape of Bevy's `add_systems(Update, (a, b, c))`:
  ///
  /// ```dart
  /// app.addSystems(Schedules.update, runIf: inState(GameStatus.playing), [
  ///   tickActionStateSystem,
  ///   resolveHitsSystem,
  ///   applyDamageSystem,
  /// ], chained: true);
  /// ```
  ///
  /// With [chained], each system is constrained to run `after` the previous
  /// one (Bevy's `.chain()`); otherwise order within the batch is left to the
  /// scheduler. Systems needing individual `after`/`before` constraints or
  /// their own condition still register through [AppBuilder.addSystem].
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
