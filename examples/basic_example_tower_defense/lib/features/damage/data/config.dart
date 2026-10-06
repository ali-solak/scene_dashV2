library;

import 'package:vector_math/vector_math.dart' show Vector4;

const double hitFlashSeconds = 0.08;
const double popSeconds = 0.25;
const double popScale = 2.2;

const double shieldRegenDelay = 2.5;
const double shieldRegenPerSecond = 8;
const double shieldBubbleRadius = 1.3;

final Vector4 hitFlashGlow = Vector4(2.5, 2.2, 1.8, 1);
final Vector4 popColor = Vector4(1.0, 0.75, 0.45, 1);
final Vector4 shieldColor = Vector4(0.35, 0.85, 1.0, 0.35);
