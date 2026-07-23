/// Common [RunCondition] builders.
library;

import '../time/fixed_time.dart';
import '../time/frame_time.dart';
import '../world/world.dart';
import 'system_registration.dart';

/// A condition that passes when [condition] does not.
RunCondition not(RunCondition condition) =>
    (World world) => !condition(world);

/// Passes once every [seconds] of game time.
///
/// Each registration has its own clock. Overshoot carries into the next period.
/// In an `and` condition, place [every] first if it should keep advancing while
/// the other condition is false.
RunCondition every(double seconds) {
  assert(seconds > 0, 'every() needs a positive period.');
  var accumulated = 0.0;
  return (World world) {
    accumulated += world.fixedContext
        ? world.resource<FixedTime>().delta
        : world.resource<FrameTime>().delta;
    if (accumulated < seconds) return false;
    accumulated -= seconds;
    return true;
  };
}

/// Passes while the event channel for [T] has buffered events.
RunCondition hasEvents<T>() =>
    (World world) => world.eventChannel<T>().isNotEmpty;

/// Passes while a resource of type [T] is registered.
RunCondition hasResource<T extends Object>() =>
    (World world) => world.hasResource<T>();

/// Short-circuiting composition of [RunCondition]s.
extension RunConditionOps on RunCondition {
  /// Passes when both conditions pass.
  RunCondition and(RunCondition other) =>
      (World world) => this(world) && other(world);

  /// Passes when either condition passes.
  RunCondition or(RunCondition other) =>
      (World world) => this(world) || other(world);
}
