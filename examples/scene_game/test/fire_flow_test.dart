import 'package:flutter_test/flutter_test.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';
import 'package:scene_game/common/game_state.dart';
import 'package:scene_game/features/projectiles/projectiles.dart';

void main() {
  ({TestGame game, Blaster blaster, List<BlasterShots> fired}) build() {
    final blaster = Blaster();
    final fired = <BlasterShots>[];
    void probe(World world) {
      final buttons = world.buttons<GameAction>();
      final shots = blaster.update(
        pressed: buttons.justPressed(GameAction.fire),
        released: buttons.justReleased(GameAction.fire),
        held: buttons.pressed(GameAction.fire),
        dt: world.dt,
      );
      if (!shots.isEmpty) fired.add(shots);
    }

    final game = TestGame.headless(
      features: [
        (g) => g.addSystem(Schedules.fixedUpdate, probe, reads: const {}),
      ],
    );
    return (game: game, blaster: blaster, fired: fired);
  }

  test('hold-charge-release through the frame loop fires a shot', () {
    final g = build();
    g.game.pump();
    g.game.press(GameAction.fire);
    g.game.pump();
    g.game.pumpFixed(steps: 40);
    expect(g.blaster.isCharging, isTrue);

    g.game.release(GameAction.fire);
    g.game.pump();
    expect(g.fired, isNotEmpty);
  });

  test('a canceled hold aborts the charge without firing', () {
    final g = build();
    g.game.pump();
    g.game.press(GameAction.fire);
    g.game.pump();
    g.game.pumpFixed(steps: 40);

    g.game.world.buttons<GameAction>().cancel(GameAction.fire);
    g.game.pump();
    expect(g.fired, isEmpty);
    expect(g.blaster.isReady, isTrue);
  });

  test('a tap landing on zero-fixed-step frames still fires', () {
    final g = build();
    g.game.pump();
    g.game
      ..press(GameAction.fire)
      ..release(GameAction.fire);
    g.game.pump(dt: 1 / 240);
    g.game.pump(dt: 1 / 240);
    g.game.pump(dt: 1 / 60);
    expect(g.fired, isNotEmpty);
  });
}
