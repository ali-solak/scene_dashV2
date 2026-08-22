library;

import 'package:vector_math/vector_math.dart' show Vector4;

const int towerCost = 40;
const double towerRange = 6.5;
const double towerDamage = 12;
const double towerCooldownSeconds = 0.6;
const double towerRadius = 0.7;

const double towerFootprint = towerRadius * 2.2;
const double beamSeconds = 0.18;
const double beamThickness = 0.09;

final Vector4 towerColor = Vector4(0.35, 0.70, 0.95, 1);
final Vector4 beamColor = Vector4(1.0, 0.85, 0.45, 0);
