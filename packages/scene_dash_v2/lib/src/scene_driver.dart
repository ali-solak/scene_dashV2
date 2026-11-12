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
  final PhysicsStepMirror _physicsMirror = PhysicsStepMirror();
  int _stepsThisFrame = 0;

  EcsSceneDriver(
    this._loop, {
    this.fixedTimestep = 1.0 / 60.0,
    this.maxSubsteps = 8,
  });

  @override
  void fixedUpdate(double fixedDt) {
    _stepsThisFrame++;
    _loop.fixedStep(fixedDt);
  }

  @override
  void update(double deltaSeconds) {
    final physics = isMounted ? node.getComponent<PhysicsWorld>() : null;
    final double alpha;
    if (physics != null) {
      _accumulator = 0;
      alpha = _physicsMirror.advance(
        frameDt: deltaSeconds,
        steps: _stepsThisFrame,
        fixedTimestep: physics.fixedTimestep,
        maxSubsteps: physics.maxSubsteps,
      );
    } else {
      _physicsMirror.reset();
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
    _stepsThisFrame = 0;
    _loop.update(deltaSeconds, fixedAlpha: alpha.clamp(0.0, 1.0));
  }
}

final class PhysicsStepMirror {
  double _accumulator = 0;

  double advance({
    required double frameDt,
    required int steps,
    required double fixedTimestep,
    required int maxSubsteps,
  }) {
    var accumulator = _accumulator + frameDt - steps * fixedTimestep;
    if (accumulator > fixedTimestep * maxSubsteps || accumulator < 0) {
      accumulator = 0;
    }
    _accumulator = accumulator;
    return accumulator / fixedTimestep;
  }

  void reset() => _accumulator = 0;
}
