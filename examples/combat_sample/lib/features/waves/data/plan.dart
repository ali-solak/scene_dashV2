part of '../waves.dart';

sealed class WaveStep extends Step<WaveStep> {
  const WaveStep();
}

final class HealPlayer extends WaveStep {
  const HealPlayer();
}

final class FieldWave extends WaveStep {
  const FieldWave();
}

final class UntilCleared extends WaveStep {
  const UntilCleared();
}

final class Breather extends WaveStep {
  const Breather(this.seconds);

  final double seconds;
}

/// The endless run. A different const here is a different game mode.
const endlessRun = Repeat(
  Sequence([
    HealPlayer(),
    FieldWave(),
    UntilCleared(),
    Breather(waveIntermissionSeconds),
  ]),
);
