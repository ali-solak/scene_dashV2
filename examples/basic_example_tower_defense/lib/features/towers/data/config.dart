library;

import 'package:vector_math/vector_math.dart' show Vector4;

enum TowerKind {
  bolt(label: 'bolt', cost: 40, health: 40),
  pulse(label: 'pulse', cost: 60, health: 50),
  shield(label: 'shield', cost: 50, health: 30);

  const TowerKind({
    required this.label,
    required this.cost,
    required this.health,
  });

  final String label;
  final int cost;
  final double health;
}

const double towerRadius = 0.7;
const double towerFootprint = towerRadius * 2.2;
const double boardEdge = 17;

const double boltRange = 6.5;
const double boltDamage = 12;
const double boltCooldownSeconds = 0.6;
const double beamSeconds = 0.18;
const double beamThickness = 0.09;

const double pulseRange = 3.6;
const double pulseDamage = 9;
const double pulseCooldownSeconds = 1.4;
const double pulseRingSeconds = 0.35;

const double shieldRange = 5;
const double shieldStrength = 30;

final Vector4 boltColor = Vector4(0.35, 0.70, 0.95, 1);
final Vector4 pulseColor = Vector4(0.95, 0.60, 0.25, 1);
final Vector4 shieldTowerColor = Vector4(0.35, 0.90, 0.80, 1);
final Vector4 beamColor = Vector4(1.0, 0.85, 0.45, 0);
final Vector4 ringColor = Vector4(1.0, 0.65, 0.30, 0);
final Vector4 ghostOkColor = Vector4(0.35, 0.95, 0.55, 0.45);
final Vector4 ghostBlockedColor = Vector4(0.95, 0.30, 0.30, 0.45);

enum Refusal {
  gold('not enough gold'),
  edge('off the board'),
  road('too close to the road'),
  decor('something is in the way'),
  occupied('a tower is already there');

  const Refusal(this.reason);

  final String reason;
}
