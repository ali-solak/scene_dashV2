part of '../waves.dart';

enum WavePhase { breather, attacking }

final class Wave {
  int number = 0;
  int left = 0;
  final Machine<WavePhase> phase = Machine(WavePhase.breather);

  double get nextWaveIn => breatherSeconds - phase.elapsed;
}
