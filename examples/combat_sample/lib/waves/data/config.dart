part of '../waves.dart';

/// How many barbarians wave [wave] fields, capped by the model pool /
/// theater budget (L4 says the fight stays readable — more than a
/// handful of live agents is noise, not difficulty).
const int baseWaveEnemies = 2;
const int maxWaveEnemies = 6;

int enemiesForWave(int wave) =>
    math.min(maxWaveEnemies, baseWaveEnemies + (wave - 1) ~/ 2);

/// Imported skinned models cannot be cloned, so each live barbarian
/// borrows one from a pool.
///
/// The death window is tuned to end inside the breather (see
/// `dissolveSeconds`), so in principle a wave's corpses are gone before
/// the next one needs their models. The headroom is for the cases where
/// that reasoning does not hold exactly — hitstop freezes game time, so
/// a bloody wave-clear stretches both clocks unevenly. Running out means
/// visible graybox capsules mid-fight, which is worth a few megabytes to
/// never see.
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
