import 'package:flutter_test/flutter_test.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';
import 'package:scene_game/game/game_state.dart';
import 'package:scene_game/projectiles/projectiles.dart';

/// Drives the real event → Blaster path through the real frame pipeline —
/// no scene, GPU, physics or player entity — to reproduce "charging works,
/// no projectiles fired". A probe system mimics `shootProjectiles`: consume
/// the fire edges, read the held level, call [Blaster.update], record any
/// shots.
void main() {
  ({TestGame game, Blaster blaster, List<BlasterShots> fired}) build() {
    final blaster = Blaster();
    final fired = <BlasterShots>[];
    void probe(World world) {
      var pressed = false;
      var released = false;
      var canceled = false;
      for (final _ in world.events<FirePressed>()) {
        pressed = true;
      }
      for (final _ in world.events<FireReleased>()) {
        released = true;
      }
      for (final _ in world.events<FireCanceled>()) {
        canceled = true;
      }
      final shots = blaster.update(
        pressed: pressed,
        released: released,
        canceled: canceled,
        held: world.buttons<GameAction>().pressed(GameAction.fire),
        dt: world.dt,
      );
      if (!shots.isEmpty) fired.add(shots);
    }

    final game = TestGame.headless(features: [
      (g) => g
        // The device wiring: fire edges must survive until a fixed step
        // consumes them, however many frames that takes.
        ..configureEvent<FirePressed>(retainedUpdates: null)
        ..configureEvent<FireReleased>(retainedUpdates: null)
        ..configureEvent<FireCanceled>(retainedUpdates: null)
        ..addSystem(Schedules.fixedUpdate, probe, reads: const {}),
    ]);
    return (game: game, blaster: blaster, fired: fired);
  }

  test('hold-charge-release through the frame loop fires a shot', () {
    final g = build();
    // One boot frame first: `world.events<T>()` readers register at a
    // system's first run, and events sent before any reader exists expire
    // at the frame's event maintenance. On device input always arrives
    // after the first frame, so the test starts there too.
    g.game.pump();

    // Press: the widget sets the held level and emits the edge, between
    // frames.
    g.game.setPressed(GameAction.fire, down: true);
    g.game.emit(const FirePressed());

    g.game.pump(); // consumes FirePressed → charging
    g.game.pumpFixed(steps: 40); // ~0.68s of holding, past the threshold
    expect(g.blaster.isCharging, isTrue, reason: 'charging works');

    // Release.
    g.game.setPressed(GameAction.fire, down: false);
    g.game.emit(const FireReleased());
    g.game.pump();

    expect(g.fired, isNotEmpty, reason: 'release should fire a charged shot');
  });

  test('release landing on a zero-fixed-step frame still fires '
      '(null retention)', () {
    final g = build();
    g.game.pump(); // start clean so the tap frames are the interesting ones

    // Quick tap: press+release between frames.
    g.game.setPressed(GameAction.fire, down: true);
    g.game.emit(const FirePressed());
    g.game.setPressed(GameAction.fire, down: false);
    g.game.emit(const FireReleased());

    // Two short frames that accumulate less than a fixed step each: NO
    // fixed step runs, so nothing consumes the edges yet.
    g.game.pump(dt: 1 / 240);
    g.game.pump(dt: 1 / 240);
    // Finally a frame with a fixed step.
    g.game.pump(dt: 1 / 60);

    expect(g.fired, isNotEmpty, reason: 'edge must survive zero-step frames');
  });
}
