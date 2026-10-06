library;

const double breatherSeconds = 6;
const double spawnGapSeconds = 0.35;

const int firstWaveSize = 10;
const int waveSizeGrowth = 4;
const double waveHealthGrowth = 0.2;
const int waveBonusPerWave = 15;
const int raidersFromWave = 2;
const int raiderEvery = 5;

int waveSize(int wave) => firstWaveSize + (wave - 1) * waveSizeGrowth;

double waveHealthScale(int wave) => 1 + (wave - 1) * waveHealthGrowth;

int waveBonus(int wave) => wave * waveBonusPerWave;

bool isRaider(int wave, int index) =>
    wave >= raidersFromWave && index % raiderEvery == raiderEvery - 1;
