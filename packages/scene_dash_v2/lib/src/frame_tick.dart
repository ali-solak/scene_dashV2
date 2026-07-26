import 'package:flutter/foundation.dart' show ChangeNotifier;

/// Notifies listeners after each rendered frame.
final class FrameTickNotifier extends ChangeNotifier {
  /// Notifies all listeners.
  void pulse() => notifyListeners();
}
