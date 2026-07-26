/// Headless game support.
library;

import '../app/app.dart';
import '../diagnostics/app_diagnostics.dart';
import '../input/button_input.dart';
import '../input/input_buffer.dart';
import '../schedule/access_conflict.dart';
import '../schedule/schedules.dart';
import '../time/fixed_time.dart';
import '../time/frame_time.dart';
import '../time/game_clock.dart';
import '../world/world.dart';
import 'game_builder.dart';
import 'remove_after.dart';
import 'spawning.dart';

/// Runs game logic without Flutter.
final class TestGame {
  /// The app under test.
  final App app;

  /// Feature registration.
  late final GameBuilder builder;

  /// The fixed timestep, in seconds.
  final double fixedDt;

  bool _started = false;
  double _accumulator = 0;
  Duration _elapsed = Duration.zero;

  /// Creates a headless game with [features].
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

  // Input

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

  /// Sends [event] into the world.
  void emit<E extends Object>(E event) {
    if (E == event.runtimeType) world.registerEvent<E>();
    world.sendEvent(event);
  }

  // Frames

  void _boundary() => SpawnQueue.of(world).flush();

  /// Runs startup once.
  void start() {
    if (_started) return;
    _started = true;
    _boundary();
    app.start(onStartupFlushed: _boundary);
    _boundary();
  }

  /// Advances one frame by [dt].
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
    // Age inputs before frame start.
    advanceInputBuffers(world.resources.values, dt);
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
      // Refreshes win before deadlines advance.
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

  /// Advances [steps] frames using [fixedDt].
  void pumpFixed({required int steps}) {
    for (var i = 0; i < steps; i++) {
      pump(dt: fixedDt);
    }
  }

  /// Runs the shutdown schedule and cleanups once.
  Future<void> shutdown() => app.shutdown();
}
