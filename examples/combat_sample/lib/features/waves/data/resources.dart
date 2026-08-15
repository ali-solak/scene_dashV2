part of '../waves.dart';

/// The run's wave clock: which wave is live, and the breather between
/// them. A plain resource; the wave system writes it, the HUD reads it.
final class WaveState {
  /// 0 before the first wave has been fielded.
  int wave = 0;

  double intermission = 0;

  /// Where the run is in [endlessRun]. Private to this feature: nothing
  /// outside the wave system reads the step it is on.
  final Routine<WaveStep> routine = Routine(endlessRun);

  bool get inIntermission => intermission > 0;

  /// True once a wave has been spawned and its barbarians are still up.
  bool get engaged =>
      routine.current is UntilEngaged || routine.current is UntilCleared;

  void reset() {
    wave = 0;
    intermission = 0;
    routine.restart();
  }
}
