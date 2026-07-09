import 'package:flutter_scene/scene.dart' show Component, PhysicsWorld;

import 'package:scene_dash_v2_core/advanced.dart';


/// The single internal `flutter_scene` [Component] that drives Scene-Dash from
/// the scene lifecycle. Attached to the scene root by [Game.start].
///
/// `flutter_scene` calls [fixedUpdate] each fixed step (before its physics
/// step, possibly several times per frame) and [update] once per frame after
/// interpolation. But the scene only *walks* `fixedUpdate` while a
/// [PhysicsWorld] component is attached — without one, its physics driver
/// returns before taking a single step. A game with no physics engine
/// (kinematic locomotion, gameplay-owned hit volumes) still needs its
/// fixed-step schedules, so when no [PhysicsWorld] is present this driver
/// runs its own accumulator over the same [deltaSeconds] the scene hands it:
/// same step size, same substep cap, and same spiral-of-death drop as
/// `Scene.advancePhysics`. The delta arrives already `GameClock`-scaled, so
/// pause/hitstop suppress the self-driven steps exactly like physics ones.
///
/// With a [PhysicsWorld] attached, the accumulator stays empty and the scene
/// remains the only ticker — the two paths can never double-step.
final class EcsSceneDriver extends Component {
  final EcsFrameLoop _loop;

  /// Step size for the self-driven fixed loop, in seconds. Matches
  /// [PhysicsWorld.fixedTimestep]'s default.
  final double fixedTimestep;

  /// Maximum self-driven fixed steps per frame; accumulated time beyond it
  /// is dropped, mirroring [PhysicsWorld.maxSubsteps].
  final int maxSubsteps;

  double _accumulator = 0;

  EcsSceneDriver(
    this._loop, {
    this.fixedTimestep = 1.0 / 60.0,
    this.maxSubsteps = 8,
  });

  @override
  void fixedUpdate(double fixedDt) => _loop.fixedStep(fixedDt);

  @override
  void update(double deltaSeconds) {
    if (isAttached && node.getComponent<PhysicsWorld>() != null) {
      // The scene's physics driver owns the fixed steps (they already ran
      // for this frame via [fixedUpdate]). Clear the accumulator so a world
      // added at runtime never inherits stale self-driven time.
      _accumulator = 0;
    } else {
      _accumulator += deltaSeconds;
      var steps = 0;
      while (_accumulator >= fixedTimestep && steps < maxSubsteps) {
        _loop.fixedStep(fixedTimestep);
        _accumulator -= fixedTimestep;
        steps++;
      }
      if (_accumulator > fixedTimestep * maxSubsteps) {
        // Drop unconsumed time to avoid spiralling when the renderer is
        // running far behind the fixed rate (same policy as the scene's
        // physics driver).
        _accumulator = 0;
      }
    }
    _loop.update(deltaSeconds);
  }
}
