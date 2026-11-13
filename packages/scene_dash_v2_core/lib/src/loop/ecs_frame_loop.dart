import '../app/app.dart';
import '../input/input_buffer.dart';
import '../schedule/schedules.dart';
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

  final void Function()? onFixedStepStart;

  late final InputLatch _latch = InputLatch(app.world.resources);

  EcsFrameLoop(
    this.app, {
    this.onBeforeUpdate,
    this.onCommandBoundary,
    this.onFrameEnd,
    this.onFixedStepStart,
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
    final world = app.world;
    final clock = world.clock;
    // Apply a partial freeze to its full frame.
    final scaledDelta = deltaSeconds * clock.effectiveScale;
    clock.advanceFreeze(deltaSeconds);
    world.frameTime
      ..delta = scaledDelta
      ..unscaledDelta = deltaSeconds
      ..elapsed = elapsed
      ..frame += 1;
    _latch.advanceFrame(deltaSeconds);
    app.runSchedule(Schedules.frameStart);
    app.applyStateTransitions();
    onCommandBoundary?.call();
    app.updateEvents();
    return scaledDelta;
  }

  /// Runs one fixed step.
  void fixedStep(double fixedDt) {
    onFixedStepStart?.call();
    app.world.fixedTime
      ..delta = fixedDt
      ..tick += 1;
    _latch.beginStep();
    try {
      app.runSchedule(Schedules.fixedPrePhysics);
    } finally {
      _latch.endStep();
    }
    app.world.removeAfterTrackerOrNull?.tick(fixedDt);
    onCommandBoundary?.call();
  }

  /// Per-frame update: [Schedules.postPhysics] (the frame's fixed steps and
  /// physics integration have all run by the time the scene calls this), then
  /// [onCommandBoundary], [onBeforeUpdate], [Schedules.update],
  /// [onCommandBoundary] again (where the Flutter `Game` mounts nodes spawned
  /// during `update`), [Schedules.renderSync], and finally [onFrameEnd] (e.g.
  /// flush scene-graph mutations) before render.
  ///
  /// [deltaSeconds] arrives already clock-scaled under the standard driver:
  /// it is the value [frameStart] returned, routed through `Scene.update`'s
  /// component walk. `FrameTime.unscaledDelta` (set at [frameStart]) carries
  /// this frame's wall delta.
  void update(double deltaSeconds, {double? fixedAlpha}) {
    final world = app.world;
    world.frameTime.delta = deltaSeconds;
    if (fixedAlpha != null) world.fixedTime.alpha = fixedAlpha;
    app.runSchedule(Schedules.postPhysics);
    onCommandBoundary?.call();
    onBeforeUpdate?.call();
    app.runSchedule(Schedules.update);
    onCommandBoundary?.call();
    app.runSchedule(Schedules.renderSync);
    onFrameEnd?.call();
  }
}
