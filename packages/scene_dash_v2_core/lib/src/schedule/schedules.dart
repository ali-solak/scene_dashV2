import 'schedule_label.dart';

/// Built in frame schedules.
abstract final class Schedules {
  /// Runs once, before the first frame.
  static const ScheduleLabel startup = ScheduleLabel('startup');

  /// Runs at the very start of each rendered frame (`SceneView.onTick`).
  static const ScheduleLabel frameStart = ScheduleLabel('frameStart');

  /// Runs each fixed step, before the scene's physics step.
  static const ScheduleLabel fixedPrePhysics = ScheduleLabel('fixedPrePhysics');

  /// Runs each fixed step before physics.
  static const ScheduleLabel fixedUpdate = fixedPrePhysics;

  /// Runs once per frame after physics and before [update].
  static const ScheduleLabel postPhysics = ScheduleLabel('postPhysics');

  /// Runs each frame after interpolation, during the scene component update.
  static const ScheduleLabel update = ScheduleLabel('update');

  /// Runs each frame after [update]; bridges ECS state into the scene graph.
  static const ScheduleLabel renderSync = ScheduleLabel('renderSync');

  /// Runs once, during teardown.
  static const ScheduleLabel shutdown = ScheduleLabel('shutdown');

  /// All built-in schedules in execution order.
  static const List<ScheduleLabel> all = <ScheduleLabel>[
    startup,
    frameStart,
    fixedPrePhysics,
    postPhysics,
    update,
    renderSync,
    shutdown,
  ];
}
