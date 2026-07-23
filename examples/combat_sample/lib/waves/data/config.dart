part of '../waves.dart';

/// How many barbarians wave [wave] fields, capped so the fight stays
/// readable: more than a handful of live agents is noise, not difficulty.
const int baseWaveEnemies = 2;
const int maxWaveEnemies = 6;

int enemiesForWave(int wave) =>
    math.min(maxWaveEnemies, baseWaveEnemies + (wave - 1) ~/ 2);

/// Imported skinned models cannot be cloned, so each live barbarian
/// borrows one from a pool. The headroom covers corpses still dissolving
/// when the next wave spawns (hitstop stretches the clocks unevenly);
/// running out means graybox capsules mid-fight.
const int barbarianPoolSize = maxWaveEnemies + 4;

/// Health and power ramp per wave, so wave 10 is a different fight from
/// wave 1 without new mechanics.
double healthForWave(int wave) => enemyMaxHealth * (1 + 0.22 * (wave - 1));
double powerForWave(int wave) => 1 + 0.09 * (wave - 1);

/// From this wave on, one barbarian per [giantEveryWaves] arrives as a
/// giant: it spawns normal-sized and grows on the transform clip.
const int firstGiantWave = 3;
const int giantEveryWaves = 3;

bool waveHasGiant(int wave) =>
    wave >= firstGiantWave && (wave - firstGiantWave) % giantEveryWaves == 0;

/// The breather between waves.
const double waveIntermissionSeconds = 3.0;

/// How much of the player's health a cleared wave gives back (1.0 = all of
/// it). The run is meant to be decided by the fight in front of you, not
/// by the chip damage you carried out of wave 2.
const double waveHealFraction = 1.0;

/// Barbarians walk in from this radius (outside the fighting circle, so
/// they visibly close in rather than popping into your face).
const double waveSpawnRadius = 11.0;
