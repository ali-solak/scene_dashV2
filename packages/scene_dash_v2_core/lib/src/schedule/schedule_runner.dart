import '../state/states.dart';
import '../surface/spawning.dart';
import '../world/world.dart';
import 'schedule_label.dart';
import 'schedules.dart';

/// Runs a custom schedule on demand.
///
/// Inserted by the app so systems reach the dispatcher through
/// `world.runSchedule` without holding the app itself. This is the surface
/// policy: custom labels only, and one run is a complete gameplay command
/// boundary. `App.runSchedule` (advanced.dart) is the unrestricted form the
/// frame drivers use.
final class ScheduleRunner {
  final World _world;
  final void Function(ScheduleLabel label) _run;

  ScheduleRunner(this._world, this._run);

  /// Runs the schedule [label] inline, then settles structural changes.
  ///
  /// Rejects the built-in frame schedules and state schedules: those belong
  /// to the frame driver and the state machine.
  ///
  /// State transitions are deliberately NOT applied here. A transition runs
  /// `OnExit`/`OnEnter` and despawns state-scoped entities; firing that from
  /// inside a turn would bury a second layer of schedules under this one.
  /// `setState` keeps its frame-start boundary.
  void run(ScheduleLabel label) {
    if (label is StateScheduleLabel || Schedules.all.contains(label)) {
      throw StateError(
        'runSchedule(${label.id}) targets a framework schedule. The frame '
        'driver owns the built-in slots and the state machine owns '
        'OnEnter/OnExit; pass a label registered with addSchedule. (App from '
        'advanced.dart runs any schedule, for drivers and tests.)',
      );
    }
    _run(label);
    // Spawns and adds settle here too, so back-to-back runs compose: the
    // second sees what the first spawned.
    SpawnQueue.of(_world).flush();
  }
}
