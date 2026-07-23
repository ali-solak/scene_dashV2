import '../system/system_adapter.dart';
import '../world/world.dart';
import 'system_label.dart';
import 'system_set.dart';

/// Decides whether a system runs on a given schedule pass.
///
/// Attached at registration (`addSystem(..., runIf: ...)`) and evaluated every
/// time the schedule runs, just before the system; returning `false` skips the
/// system for that pass. Conditions should be cheap reads — typically a
/// resource check:
///
/// ```dart
/// bool playing(World world) =>
///     world.resource<GameState>().status == GameStatus.playing;
///
/// app.addSystem(movePlayerSystem, schedule: Schedules.update, runIf: playing);
/// ```
typedef RunCondition = bool Function(World world);

/// A single system registered into a schedule, with its ordering constraints.
final class SystemRegistration {
  /// The adapter that initializes and runs the system.
  final SystemAdapter adapter;

  /// This system's unique label within its schedule.
  final SystemLabel label;

  /// Labels this system must run after.
  final List<SystemLabel> after;

  /// Labels this system must run before.
  final List<SystemLabel> before;

  /// Labels whose access-conflict pairing with this system is exempted:
  /// the author asserts the pair is independent (disjoint entities,
  /// disjoint fields), and the detector trusts it in both directions.
  /// Ordering is untouched; every other pairing keeps the full net.
  final List<SystemLabel> independentOf;

  /// Optional predicate gating each run; `null` means always run.
  final RunCondition? runIf;

  /// The set this system belongs to, or `null` for none. Set ordering is
  /// declared per schedule with `configureSets`.
  final SystemSet? inSet;

  const SystemRegistration({
    required this.adapter,
    required this.label,
    this.after = const <SystemLabel>[],
    this.before = const <SystemLabel>[],
    this.independentOf = const <SystemLabel>[],
    this.runIf,
    this.inSet,
  });
}
