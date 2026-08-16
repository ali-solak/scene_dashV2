import 'package:scene_dash_v2/scene_dash_v2.dart';
import 'package:vector_math/vector_math.dart' show Vector3;

import '../features/world/data/config.dart';

// Shared scratch avoids frame allocations.
final Vector3 _desired = Vector3.zero();

final class CameraRig {
  final Vector3 position = Vector3(0, 12, 24);
  final Vector3 target = Vector3(0, 0, -2);

  void reset() {
    position.setValues(0, 12, 24);
    target.setValues(0, 0, -2);
  }

  void follow(Vector3 playerPosition, double dt) {
    _desired.setValues(
      playerPosition.x * 0.55,
      playerPosition.y + 0.7,
      playerPosition.z - 2.8,
    );
    target.smoothToward(_desired, dt, cameraFollowHalfLife);

    _desired.setValues(
      playerPosition.x * 0.65,
      playerPosition.y + 10,
      playerPosition.z + 18,
    );
    position.smoothToward(_desired, dt, cameraFollowHalfLife);
  }
}
