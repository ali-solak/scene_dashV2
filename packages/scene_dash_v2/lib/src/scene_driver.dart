import 'package:flutter_scene/scene.dart' show Component;
import 'package:flutter_scene/physics.dart' show PhysicsWorld;

import 'package:scene_dash_v2_core/advanced.dart';

/// Runs ECS updates from the scene.
///
/// Uses its own fixed step loop unless it is mounted in a scene whose root
/// carries a [PhysicsWorld].
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
    final physics = isMounted ? node.getComponent<PhysicsWorld>() : null;
    final double alpha;
    if (physics != null) {
      _accumulator = 0;
      alpha = physics.interpolationAlpha;
    } else {
      _accumulator += deltaSeconds;
      var steps = 0;
      while (_accumulator >= fixedTimestep && steps < maxSubsteps) {
        _loop.fixedStep(fixedTimestep);
        _accumulator -= fixedTimestep;
        steps++;
      }
      if (_accumulator > fixedTimestep * maxSubsteps) _accumulator = 0;
      alpha = _accumulator / fixedTimestep;
    }
    _loop.update(deltaSeconds, fixedAlpha: alpha.clamp(0.0, 1.0));
  }
}
