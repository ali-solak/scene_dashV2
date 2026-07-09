import 'package:flutter_scene/scene.dart' show Component, Scene;
import 'package:flutter_test/flutter_test.dart';
import 'package:scene_dash_v2_core/advanced.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';
// Driver is intentionally not part of the public API; reach into src to verify
// the flutter_scene Component forwarding.
import 'package:scene_dash_v2/src/scene_driver.dart';

import 'support.dart';

App _appWithProbes(List<String> log) {
  return App()
    ..addSystemAdapter(
      CountAdapter('fixed', log),
      schedule: Schedules.fixedPrePhysics,
      label: const SystemLabel('p.fixed'),
    )
    ..addSystemAdapter(
      CountAdapter('update', log),
      schedule: Schedules.update,
      label: const SystemLabel('p.update'),
    )
    ..addSystemAdapter(
      CountAdapter('renderSync', log),
      schedule: Schedules.renderSync,
      label: const SystemLabel('p.renderSync'),
    );
}

void main() {
  test('EcsSceneDriver is a flutter_scene Component', () {
    final driver = EcsSceneDriver(EcsFrameLoop(App()));
    expect(driver, isA<Component>());
  });

  test('driver forwards fixedUpdate/update to the loop', () {
    final log = <String>[];
    final app = _appWithProbes(log);
    final loop = EcsFrameLoop(app)..ensureTimeResources();
    app.start();

    final driver = EcsSceneDriver(loop);
    driver.fixedUpdate(0.02);
    expect(log, <String>['fixed']);

    driver.update(0.016);
    expect(log, <String>['fixed', 'update', 'renderSync']);
  });

  test('without a PhysicsWorld the driver runs its own fixed steps', () {
    // The scene walks fixedUpdate only while a PhysicsWorld component is
    // attached; a physics-free game (kinematic movement, gameplay-owned hit
    // volumes) gets its fixed-step schedules from the driver's accumulator.
    final log = <String>[];
    final app = _appWithProbes(log);
    final loop = EcsFrameLoop(app)..ensureTimeResources();
    app.start();

    final driver = EcsSceneDriver(loop, fixedTimestep: 1 / 60);
    // One 60 Hz frame: exactly one self-driven fixed step before update.
    driver.update(1 / 60);
    expect(log, <String>['fixed', 'update', 'renderSync']);

    // A long frame is consumed in several steps.
    log.clear();
    driver.update(3 / 60);
    expect(log, <String>['fixed', 'fixed', 'fixed', 'update', 'renderSync']);

    // The remainder carries between frames: two half-step frames -> one step.
    log.clear();
    driver.update(0.5 / 60);
    expect(log, <String>['update', 'renderSync']);
    log.clear();
    driver.update(0.5 / 60);
    expect(log, <String>['fixed', 'update', 'renderSync']);
  });

  test('self-driven fixed steps stop on a zero (frozen/paused) delta', () {
    final log = <String>[];
    final app = _appWithProbes(log);
    final loop = EcsFrameLoop(app)..ensureTimeResources();
    app.start();

    final driver = EcsSceneDriver(loop, fixedTimestep: 1 / 60);
    driver.update(0); // GameClock at scale 0 hands the driver a zero delta.
    expect(log, <String>['update', 'renderSync']);
  });

  test('self-driven fixed steps are capped and drop the backlog', () {
    final log = <String>[];
    final app = _appWithProbes(log);
    final loop = EcsFrameLoop(app)..ensureTimeResources();
    app.start();

    final driver = EcsSceneDriver(loop, fixedTimestep: 1 / 60, maxSubsteps: 4);
    // A huge hitch: only maxSubsteps steps run and the leftover is dropped,
    // so the next normal frame is back to one step (no spiral).
    driver.update(20 / 60);
    expect(log.where((e) => e == 'fixed').length, 4);
    log.clear();
    driver.update(1 / 60);
    expect(log, <String>['fixed', 'update', 'renderSync']);
  });

  test('Game.shutdown runs app shutdown and removes the scene driver',
      skip: 'Constructs a real flutter_scene Scene, which needs Flutter GPU / '
          'Impeller — unavailable under headless `flutter test`. Belongs in an '
          'on-device integration_test.', () async {
    final scene = Scene();
    final game = Game(scene: scene);
    final log = <String>[];
    game.app.addSystemAdapter(
      CountAdapter('shutdown', log),
      schedule: Schedules.shutdown,
      label: const SystemLabel('p.shutdown'),
    );

    await game.start();
    expect(scene.root.getComponent<EcsSceneDriver>(), isNotNull);

    await game.shutdown();
    await game.shutdown();

    expect(log, <String>['shutdown']);
    expect(scene.root.getComponent<EcsSceneDriver>(), isNull);
  });
}
