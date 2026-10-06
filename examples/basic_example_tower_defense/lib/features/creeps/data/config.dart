library;

import 'package:vector_math/vector_math.dart' show Vector4;

const double runnerRadius = 0.32;
const double runnerHealth = 16;
const int runnerBounty = 5;

const double raiderRadius = 0.5;
const double raiderHealth = 60;
const int raiderBounty = 15;
const double raiderAggro = 5;
const double raiderReach = 1.4;
const double raiderStandOff = 1.1;
const double raiderBite = 8;
const double raiderBiteSeconds = 0.8;

const double creepMinScale = 0.55;
const double creepSpeed = 3.4;
const double raiderSpeed = 2.4;
const double creepSteering = 14;
const double creepSpacing = 0.9;
const double creepSeparationWeight = 1.6;
const double waypointReach = 1.3;
const double spawnScatter = 0.7;
const double spawnTurn = 2.39996;

final Vector4 runnerColor = Vector4(0.85, 0.30, 0.28, 1);
final Vector4 raiderColor = Vector4(0.55, 0.25, 0.80, 1);
