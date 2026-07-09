import '../app/app.dart';
import '../schedule/schedules.dart';
import '../time/fixed_time.dart';
import '../time/frame_time.dart';
import '../time/game_clock.dart';

/// Scene-free frame dispatcher: maps `flutter_scene` lifecycle callbacks onto
/// Scene-Dash schedules and updates the time resources.
///
/// Kept independent of `flutter_scene` so the frame/fixed/update dispatch is
/// unit-testable without a live `Scene` or GPU. [Game] and the internal scene
/// driver both delegate here.
final class EcsFrameLoop {
  /// The engine this loop drives.
  final App app;

  /// Optional hook called at the start of [update], before the `update`
  /// schedule. [Game] does not use it — mounting happens at every command
  /// boundary instead (see [onCommandBoundary]) — but custom drivers can hook
  /// pre-update work here.
  final void Function()? onBeforeUpdate;

  /// Called after a schedule has run and flushed ECS commands — after
  /// [frameStart], after each [fixedStep], after the `postPhysics` schedule,
  /// and after the `update` schedule.
  /// [Game] mounts newly bound scene nodes here, so nodes spawned by any
  /// schedule are parented by the time the next schedule runs (in particular,
  /// gameplay `update` systems always see already-mounted nodes).
  final void Function()? onCommandBoundary;

  /// Called at the end of [update] (after `renderSync`, before the scene
  /// renders) — a safe boundary to flush deferred scene-graph mutations.
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

  /// Frame start: apply the [GameClock] to the raw wall delta, update
  /// [FrameTime], run [Schedules.frameStart], apply pending state transitions
  /// (OnExit/OnEnter), then advance event channels for the new frame.
  ///
  /// Returns the scaled delta. The driver must feed that value — not the raw
  /// one — to the scene tick (`Scene.update`), which is what slows or halts
  /// the physics accumulator, component updates, and animations together
  /// with the ECS; [Game.onTick] does this.
  ///
  /// Transitions apply before [onCommandBoundary], so nodes spawned by
  /// `OnEnter` systems are mounted before the frame's fixed/update steps.
  double frameStart(Duration elapsed, double deltaSeconds) {
    // Advance the profiler frame counter (if profiling is enabled) at the one
    // per-frame boundary, so timings can be attributed to a frame number.
    app.profiler?.beginFrame();
    final clock = app.world.resources.get<GameClock>();
    // Read the scale before serving the freeze: a freeze shorter than one
    // frame must still freeze the frame it lands on, so any nonzero
    // remainder zeroes this frame and the wall delta is deducted after.
    final scaledDelta = deltaSeconds * clock.effectiveScale;
    clock.advanceFreeze(deltaSeconds);
    app.world.resources.get<FrameTime>()
      ..delta = scaledDelta
      ..unscaledDelta = deltaSeconds
      ..elapsed = elapsed
      ..frame += 1;
    app.runSchedule(Schedules.frameStart);
    app.applyStateTransitions();
    onCommandBoundary?.call();
    app.updateEvents();
    return scaledDelta;
  }

  /// Fixed step (before the scene physics step): update [FixedTime] and run
  /// [Schedules.fixedPrePhysics]. May run several times per frame.
  void fixedStep(double fixedDt) {
    app.world.resources.get<FixedTime>()
      ..delta = fixedDt
      ..tick += 1;
    app.runSchedule(Schedules.fixedPrePhysics);
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
