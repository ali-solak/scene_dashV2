import 'package:flutter_scene/scene.dart' show Component, PhysicsWorld;

import 'package:scene_dash_v2_core/advanced.dart';

/// Runs ECS updates from the scene.
///
/// Uses its own fixed step loop when no [PhysicsWorld] is attached.
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
      // Scene physics owns the fixed steps.
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
        // Drop excess accumulated time.
        _accumulator = 0;
      }
    }
    _loop.update(deltaSeconds);
  }
}
