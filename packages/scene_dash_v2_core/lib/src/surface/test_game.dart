/// The headless game harness: drives the exact frame pipeline the device
/// driver runs — same schedule order, same command boundaries, same clock
/// semantics — with no scene, no GPU and no Flutter.
///
/// ```dart
/// final game = TestGame.headless(features: [installCombat]);
/// game.world.spawn([Health(100), Facing(), FighterState()]);
/// game.press(CombatAction.roll);
/// game.pumpFixed(steps: 18);                 // 0.3 s at 60 Hz
/// expect(game.world.query<FighterState>().single.$2.iFramed, isTrue);
/// ```
///
/// Determinism guarantee: identical spawns + identical inputs ⇒ identical
/// runs (registration ordering; game-side RNG is the game's business).
library;

import '../app/app.dart';
import '../diagnostics/app_diagnostics.dart';
import '../input/button_input.dart';
import '../schedule/access_conflict.dart';
import '../schedule/schedules.dart';
import '../time/fixed_time.dart';
import '../time/frame_time.dart';
import '../time/game_clock.dart';
import '../world/world.dart';
import 'game_builder.dart';
import 'remove_after.dart';
import 'spawning.dart';

/// A headless Scene-Dash v2 game for tests and simulations.
///
/// [pump] advances one rendered frame (frame start → state transitions →
/// fixed steps by accumulator → update → render sync); [pumpFixed]
/// advances exactly one fixed step per frame for frame-exact timing
/// suites. Frames follow the `GameClock`, so pause, slow motion and
/// hitstop behave exactly as on device.
final class TestGame {
  /// The engine underneath — interop tier.
  final App app;

  /// The registration surface, alive until the first [pump]/[start].
  late final GameBuilder builder;

  /// The fixed timestep, in seconds.
  final double fixedDt;

  bool _started = false;
  double _accumulator = 0;
  Duration _elapsed = Duration.zero;

  /// Creates a headless game and runs [features] against its builder. The
  /// internal pipeline must be conflict-clean, so the access-conflict
  /// policy defaults to `throw`; [strictAccess] additionally rejects
  /// systems registered without `reads:`/`writes:` (§1.8).
  TestGame.headless({
    List<Feature> features = const <Feature>[],
    this.fixedDt = 1 / 60,
    bool strictAccess = false,
    AppDiagnostics diagnostics = const AppDiagnostics(),
    void Function(String message)? onDiagnostic,
    AccessConflictPolicy accessConflictPolicy = AccessConflictPolicy.error,
  }) : app = App(
         accessConflictPolicy: accessConflictPolicy,
         onDiagnostic: onDiagnostic,
         diagnostics: diagnostics,
       ) {
    final resources = app.world.resources;
    if (!resources.contains<FrameTime>()) resources.insert(FrameTime());
    if (!resources.contains<FixedTime>()) resources.insert(FixedTime());
    if (!resources.contains<GameClock>()) resources.insert(GameClock());
    SpawnQueue.of(app.world).onDiagnostic = onDiagnostic;
    builder = GameBuilder(app, strictAccess: strictAccess);
    for (final feature in features) {
      feature(builder);
    }
  }

  /// The world under test.
  World get world => app.world;

  /// The gameplay clock (pause, `timeScale`, `freezeFor` hitstop).
  GameClock get clock => world.resources.get<GameClock>();

  // ── input & events ────────────────────────────────────────────────────

  /// Marks [action] held on the `ButtonInput<T>` resource, creating the
  /// resource on first use.
  void press<T extends Object>(T action) => _input<T>().press(action);

  /// Marks [action] released.
  void release<T extends Object>(T action) => _input<T>().release(action);

  /// Drives [action] from a level source: presses when [down], releases
  /// otherwise.
  void setPressed<T extends Object>(T action, {required bool down}) =>
      _input<T>().setPressed(action, down);

  ButtonInput<T> _input<T extends Object>() =>
      world.resources.getOrInsert<ButtonInput<T>>(ButtonInput<T>.new);

  /// Sends [event] into the world — the widget-to-gameplay path. The
  /// channel registers on first use.
  void emit<E extends Object>(E event) {
    if (E == event.runtimeType) world.registerEvent<E>();
    world.sendEvent(event);
  }

  // ── driving ───────────────────────────────────────────────────────────

  void _boundary() => SpawnQueue.of(world).flush();

  /// Compiles schedules and runs startup once. Spawns queued by features
  /// apply first, so startup systems see them; startup spawns flush before
  /// the initial `OnEnter` schedules, so enter systems see them too.
  /// Called automatically by the first [pump].
  void start() {
    if (_started) return;
    _started = true;
    _boundary();
    app.start(onStartupFlushed: _boundary);
    _boundary();
  }

  /// Advances one rendered frame of [dt] wall seconds, replaying the
  /// device pipeline exactly: clock scale + freeze service, `frameStart`,
  /// state transitions, event maintenance, the accumulator's fixed steps,
  /// `postPhysics`, `update`, `renderSync` — with a command boundary after
  /// every flush, where spawn lists apply and owned subtrees die.
  void pump({double dt = 1 / 60}) {
    start();
    app.profiler?.beginFrame();
    final gameClock = clock;
    final scaled = dt * gameClock.effectiveScale;
    gameClock.advanceFreeze(dt);
    _elapsed += Duration(
      microseconds: (dt * Duration.microsecondsPerSecond).round(),
    );
    world.resources.get<FrameTime>()
      ..delta = scaled
      ..unscaledDelta = dt
      ..elapsed = _elapsed
      ..frame += 1;
    app.runSchedule(Schedules.frameStart);
    app.applyStateTransitions();
    _boundary();
    app.updateEvents();
    _accumulator += scaled;
    final fixedTime = world.resources.get<FixedTime>();
    while (_accumulator >= fixedDt) {
      _accumulator -= fixedDt;
      fixedTime
        ..delta = fixedDt
        ..tick += 1;
      app.runSchedule(Schedules.fixedUpdate);
      // removeAfter: deadlines advance after the schedule (a same-step
      // refresh beats expiry) and expiries flush with this boundary —
      // exactly the device driver's fixedStep.
      world.resources.tryGet<RemoveAfterTracker>()?.tick(fixedDt);
      _boundary();
    }
    world.resources.get<FrameTime>().delta = scaled;
    app.runSchedule(Schedules.postPhysics);
    _boundary();
    app.runSchedule(Schedules.update);
    _boundary();
    app.runSchedule(Schedules.renderSync);
    _boundary();
  }

  /// Advances [steps] frames of exactly one fixed step each (`dt ==`
  /// [fixedDt]) — the frame-exact idiom for timing suites. Under a freeze
  /// or pause the frames still render but no fixed steps run, exactly as
  /// on device.
  void pumpFixed({required int steps}) {
    for (var i = 0; i < steps; i++) {
      pump(dt: fixedDt);
    }
  }

  /// Runs the shutdown schedule and cleanups once.
  Future<void> shutdown() => app.shutdown();
}
