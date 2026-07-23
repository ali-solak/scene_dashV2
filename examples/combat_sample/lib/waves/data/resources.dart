part of '../waves.dart';

/// The run's wave clock: which wave is live, and the breather between
/// them. A plain resource; the wave system writes it, the HUD reads it.
final class WaveState {
  /// 0 before the first wave has been fielded.
  int wave = 0;

  /// Seconds left of the breather before the next wave walks in.
  double intermission = 0;

  /// True once a wave has been spawned and its barbarians are still up.
  bool engaged = false;

  bool get inIntermission => intermission > 0;

  void reset() {
    wave = 0;
    intermission = 0;
    engaged = false;
  }
}
