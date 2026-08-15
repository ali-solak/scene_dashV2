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

/// Spawns are queued, so a wave is not on the field the tick it is sent.
final class UntilEngaged extends WaveStep {
  const UntilEngaged();
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
    UntilEngaged(),
    UntilCleared(),
    Breather(waveIntermissionSeconds),
  ]),
);
