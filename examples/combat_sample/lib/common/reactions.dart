import 'dart:math' as math;

import 'package:scene_dash_v2/scene_dash_v2.dart' show Tag;
import 'package:vector_math/vector_math.dart' show Vector3;

const double recoilPeakSeconds = 0.05;

final class HitFlash implements Tag {
  const HitFlash();
}

final class HitPause implements Tag {
  const HitPause();
}

final class Recoil {
  Recoil(this.direction, this.strength);

  final Vector3 direction;
  double strength;
  double age = 0;

  double get offset {
    final t = age / recoilPeakSeconds;
    return strength * t * math.exp(1 - t);
  }

  void restart(Vector3 towards, double newStrength) {
    direction.setFrom(towards);
    strength = newStrength;
    age = 0;
  }
}
