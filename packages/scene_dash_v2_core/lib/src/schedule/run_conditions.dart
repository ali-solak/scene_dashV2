/// Combinators and common building blocks for [RunCondition]s.
///
/// Conditions compose with [RunConditionOps.and] / [RunConditionOps.or] and
/// invert with [not], so a gate like "playing, unless a cutscene is showing"
/// stays declarative at the registration site:
///
/// ```dart
/// app.addSystem(steerEnemiesSystem,
///     schedule: Schedules.update,
///     runIf: inState(GamePhase.overworld).and(not(cutsceneActive)));
/// ```
library;

import '../time/fixed_time.dart';
import '../time/frame_time.dart';
import '../world/world.dart';
import 'system_registration.dart';

/// A condition that passes when [condition] does not.
RunCondition not(RunCondition condition) =>
    (World world) => !condition(world);

/// A condition that passes once every [seconds] of game time — Bevy's
/// `on_timer`, for periodic systems (spawners, autosaves, AI re-planning)
/// without a timer resource to declare and tick.
///
/// ```dart
/// app.addSystem(spawnWaveSystem,
///     schedule: Schedules.update, runIf: every(2.5));
/// ```
///
/// The accumulator lives in the returned closure, so every registration gets
/// its own independent period; the first pass comes after one full period,
/// not immediately. Firing *subtracts* [seconds] instead of zeroing the
/// accumulator, so the leftover carries over and the average rate stays exact
/// over any span — no drift. Schedule-aware (D7): inside a fixed schedule it
/// advances by `FixedTime.delta` per step, elsewhere by `FrameTime.delta` —
/// both game time, so pause and slow motion stretch the period.
///
/// Composes with [RunConditionOps.and]/[RunConditionOps.or]/[not] like any
/// other condition, with one caveat: the clock only advances on evaluations
/// that reach it, and `.and` short-circuits — write `every(x).and(gate)`
/// rather than `gate.and(every(x))` if the period should keep elapsing while
/// the gate is closed.
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

/// A condition that passes while the event channel for [T] buffers any
/// events — Bevy's `on_event`.
///
/// Keyed off the channel buffer: `true` while any event is still buffered —
/// events not yet consumed by every reader, capped by the retention window
/// (under the default retention, the frame an event is sent plus the
/// following one). The channel must have been registered with
/// `addEvent<T>()`; the condition throws otherwise, so a typo'd event type
/// fails loudly rather than silently never running.
///
/// ```dart
/// app.addSystem(playHitEffectsSystem,
///     schedule: Schedules.update, runIf: hasEvents<HitEvent>());
/// ```
RunCondition hasEvents<T>() =>
    (World world) => world.eventChannel<T>().isNotEmpty;

/// Short-circuiting composition of [RunCondition]s.
extension RunConditionOps on RunCondition {
  /// Passes only when both this condition and [other] pass. [other] is not
  /// evaluated when this condition fails.
  RunCondition and(RunCondition other) =>
      (World world) => this(world) && other(world);

  /// Passes when either this condition or [other] passes. [other] is not
  /// evaluated when this condition passes.
  RunCondition or(RunCondition other) =>
      (World world) => this(world) || other(world);
}
