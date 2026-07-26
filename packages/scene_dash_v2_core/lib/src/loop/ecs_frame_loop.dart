import '../app/app.dart';
import '../input/input_buffer.dart';
import '../schedule/schedules.dart';
import '../surface/remove_after.dart';
import '../time/fixed_time.dart';
import '../time/frame_time.dart';
import '../time/game_clock.dart';

/// Runs frame schedules and updates time.
final class EcsFrameLoop {
  /// The engine this loop drives.
  final App app;

  /// Runs before the update schedule.
  final void Function()? onBeforeUpdate;

  /// Runs after each command flush.
  final void Function()? onCommandBoundary;

  /// Runs after render sync.
  final void Function()? onFrameEnd;

  EcsFrameLoop(
    this.app, {
    this.onBeforeUpdate,
    this.onCommandBoundary,
    this.onFrameEnd,
  });

  /// Inserts default [FrameTime]/[FixedTime]/[GameClock] resources if a
  /// plugin has not already provided them. Call before [App.start].
  void ensureTimeResources() {
    final resources = app.world.resources;
    if (!resources.contains<FrameTime>()) resources.insert(FrameTime());
    if (!resources.contains<FixedTime>()) resources.insert(FixedTime());
    if (!resources.contains<GameClock>()) resources.insert(GameClock());
  }

  /// Starts a frame and returns its scaled delta.
  double frameStart(Duration elapsed, double deltaSeconds) {
    // Advance the profiler frame counter (if profiling is enabled) at the one
    // per-frame boundary, so timings can be attributed to a frame number.
    app.profiler?.beginFrame();
    final clock = app.world.resources.get<GameClock>();
    // Apply a partial freeze to its full frame.
    final scaledDelta = deltaSeconds * clock.effectiveScale;
    clock.advanceFreeze(deltaSeconds);
    app.world.resources.get<FrameTime>()
      ..delta = scaledDelta
      ..unscaledDelta = deltaSeconds
      ..elapsed = elapsed
      ..frame += 1;
    // Age inputs before frame start.
    advanceInputBuffers(app.world.resources.values, deltaSeconds);
    app.runSchedule(Schedules.frameStart);
    app.applyStateTransitions();
    onCommandBoundary?.call();
    app.updateEvents();
    return scaledDelta;
  }

  /// Runs one fixed step.
  void fixedStep(double fixedDt) {
    app.world.resources.get<FixedTime>()
      ..delta = fixedDt
      ..tick += 1;
    app.runSchedule(Schedules.fixedPrePhysics);
    app.world.resources.tryGet<RemoveAfterTracker>()?.tick(fixedDt);
    onCommandBoundary?.call();
  }

  /// Per-frame update: [Schedules.postPhysics] (the frame's fixed steps and
  /// physics integration have all run by the time the scene calls this), then
  /// [onCommandBoundary], [onBeforeUpdate], [Schedules.update],
  /// [onCommandBoundary] again (where [Game] mounts nodes spawned during
  /// `update`), [Schedules.renderSync], and finally [onFrameEnd] (e.g. flush
  /// scene-graph mutations) before render.
  ///
  /// [deltaSeconds] arrives already clock-scaled under the standard driver:
  /// it is the value [frameStart] returned, routed through `Scene.update`'s
  /// component walk. `FrameTime.unscaledDelta` (set at [frameStart]) carries
  /// this frame's wall delta.
  void update(double deltaSeconds) {
    app.world.resources.get<FrameTime>().delta = deltaSeconds;
    app.runSchedule(Schedules.postPhysics);
    onCommandBoundary?.call();
    onBeforeUpdate?.call();
    app.runSchedule(Schedules.update);
    onCommandBoundary?.call();
    app.runSchedule(Schedules.renderSync);
    onFrameEnd?.call();
  }
}
