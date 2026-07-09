import 'package:flutter/foundation.dart' show ChangeNotifier;

/// The presentation heartbeat behind [Game.frameTick]: a [ChangeNotifier]
/// pulsed once at the end of every rendered frame (after `renderSync`, at the
/// scene-command flush boundary).
///
/// UI that reads live world state every frame — an FPS counter, a boss health
/// bar during a fight — listens here and *pulls* the value it needs, instead of
/// the world *pushing* per-frame snapshots out through notifiers. Only the
/// integration package knows when a frame has fully ended, which is why the
/// heartbeat lives on [Game].
///
/// Internal: [Game] owns the single instance and exposes it only as a
/// `Listenable`, so callers can listen but not pulse it.
final class FrameTickNotifier extends ChangeNotifier {
  /// Notifies all listeners. Called by [Game] at frame end; not part of the
  /// public surface.
  void pulse() => notifyListeners();
}
