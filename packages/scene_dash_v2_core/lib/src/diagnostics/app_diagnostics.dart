import 'system_profiler.dart';

/// Opt-in diagnostics configuration for an [App].
///
/// Profiling and slow-system warnings are off by default and add no per-system
/// work when disabled. Enable them from application/debug configuration:
///
/// ```dart
/// final app = App(
///   diagnostics: const AppDiagnostics(profileSystems: true),
/// );
/// // later: app.profiler?.timings
/// ```
final class AppDiagnostics {
  const AppDiagnostics({
    this.profileSystems = false,
    this.slowSystemThreshold,
    this.onSlowSystem,
  });

  /// When true, the app measures each system's execution time per schedule and
  /// exposes a [SystemProfiler] (via `App.profiler` and as a `@Resource()`).
  final bool profileSystems;

  /// When set (and [profileSystems] is true), a run exceeding this duration
  /// triggers [onSlowSystem] (or the app's `onDiagnostic` sink if that is null).
  final Duration? slowSystemThreshold;

  /// Optional sink for slow-system warnings. Defaults to the app's `onDiagnostic`.
  final void Function(SlowSystemEvent event)? onSlowSystem;
}
