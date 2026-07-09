import 'schedule_label.dart';

/// The built-in frame schedules, in their conceptual execution order.
///
/// Note the granularity split around physics: [fixedPrePhysics] is *per fixed
/// step*, while [postPhysics] is *per frame*. A per-step `fixedPostPhysics`
/// would need a post-step lifecycle hook inside the scene's physics loop,
/// which `flutter_scene` does not expose; until it does, that variant stays
/// future work and [postPhysics] is the post-physics boundary.
abstract final class Schedules {
  /// Runs once, before the first frame.
  static const ScheduleLabel startup = ScheduleLabel('startup');

  /// Runs at the very start of each rendered frame (`SceneView.onTick`).
  static const ScheduleLabel frameStart = ScheduleLabel('frameStart');

  /// Runs each fixed step, before the scene's physics step.
  static const ScheduleLabel fixedPrePhysics = ScheduleLabel('fixedPrePhysics');

  /// The v2 name for [fixedPrePhysics] — the same label, so both spellings
  /// register into the same schedule. Gameplay windows tick here.
  static const ScheduleLabel fixedUpdate = fixedPrePhysics;

  /// Runs once per frame — not per fixed step — after all of the frame's
  /// fixed steps and the scene's physics integration, before [update].
  ///
  /// The place to read physics results (post-integration transforms, drained
  /// contacts) before gameplay reacts to them.
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
