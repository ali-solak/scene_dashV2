part of '../waves.dart';

const int baseWaveEnemies = 2;
const int maxWaveEnemies = 6;

int enemiesForWave(int wave) =>
    math.min(maxWaveEnemies, baseWaveEnemies + (wave - 1) ~/ 2);

const int barbarianPoolSize = maxWaveEnemies + 4;

double healthForWave(int wave) => enemyMaxHealth * (1 + 0.22 * (wave - 1));
double powerForWave(int wave) => 1 + 0.09 * (wave - 1);

const int firstGiantWave = 3;
const int giantEveryWaves = 3;

bool waveHasGiant(int wave) =>
    wave >= firstGiantWave && (wave - firstGiantWave) % giantEveryWaves == 0;

const double waveIntermissionSeconds = 3.0;

const double waveHealFraction = 1.0;

const double waveSpawnRadius = 11.0;
