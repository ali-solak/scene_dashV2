import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';
import 'package:scene_game/collectables/collectables.dart';
import 'package:scene_game/game/game_state.dart';
import 'package:scene_game/hud/debug_panel.dart';
import 'package:scene_game/hud/game_hud.dart';
import 'package:scene_game/projectiles/data/config.dart';
import 'package:scene_game/projectiles/projectiles.dart';

/// Widget coverage for the HUD: control placement, hold/release/cancel
/// fire transitions, charge/cooldown/ready presentation, and the
/// playing/lost routing — all selected through the world from the real
/// feature resources, exactly as the shipped HUD reads them.
void main() {
  Future<WorldGame> bootHud() => WorldGame.boot(
    features: [
      (g) {
        g.addState<GameStatus>(GameStatus.playing);
        g.world
          ..insert(GameState())
          ..insert(FpsCounter())
          ..insert(Blaster())
          ..insert(ShieldState());
      },
    ],
  );

  void drive(WorldGame game, [int frames = 1]) {
    for (var i = 0; i < frames; i++) {
      game.onTick(Duration(milliseconds: 16 * (i + 1)), 1 / 60);
    }
  }

  Future<void> pumpHud(
    WidgetTester tester,
    WorldGame game, {
    void Function(bool)? onFireChanged,
    VoidCallback? onFireCanceled,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GameScope(
            game: game,
            child: BlocProvider(
              create: (_) => DebugCubit(),
              child: GameHud(
                onLeftChanged: (_) {},
                onRightChanged: (_) {},
                onFireChanged: onFireChanged ?? (_) {},
                onFireCanceled: onFireCanceled ?? () {},
                onRestart: () {},
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('movement is bottom-left and fire is bottom-right', (
    tester,
  ) async {
    await pumpHud(tester, await bootHud());

    final left = tester.getCenter(find.byIcon(Icons.arrow_left_rounded));
    final right = tester.getCenter(find.byIcon(Icons.arrow_right_rounded));
    final fire = tester.getCenter(find.byIcon(Icons.bolt_rounded));
    final size = tester.getSize(find.byType(GameHud));

    // Movement grouped on the left, fire on the right.
    expect(left.dx, lessThan(size.width / 2));
    expect(right.dx, lessThan(size.width / 2));
    expect(fire.dx, greaterThan(size.width / 2));
    // All near the bottom.
    expect(fire.dy, greaterThan(size.height / 2));
  });

  testWidgets('touch down begins holding and release fires', (tester) async {
    final events = <bool>[];
    await pumpHud(tester, await bootHud(), onFireChanged: events.add);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byIcon(Icons.bolt_rounded)),
    );
    await tester.pump();
    expect(events.last, isTrue, reason: 'press begins holding');

    await gesture.up();
    await tester.pump();
    expect(events.last, isFalse, reason: 'release fires (ends holding)');
  });

  testWidgets('tap cancel cancels rather than fires', (tester) async {
    var canceled = false;
    final events = <bool>[];
    await pumpHud(
      tester,
      await bootHud(),
      onFireChanged: events.add,
      onFireCanceled: () => canceled = true,
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byIcon(Icons.bolt_rounded)),
    );
    await tester.pump();
    await gesture.cancel();
    await tester.pump();
    expect(canceled, isTrue);
  });

  testWidgets('charge progress is shown in the fire semantics', (tester) async {
    final handle = tester.ensureSemantics();
    final game = await bootHud();
    // Drive the real blaster to exactly 60% charge.
    const span = blasterMaxChargeDuration - blasterChargeThreshold;
    game.world.resource<Blaster>()
      ..update(
        pressed: true,
        released: false,
        canceled: false,
        held: true,
        dt: 0,
      )
      ..update(
        pressed: false,
        released: false,
        canceled: false,
        held: true,
        dt: blasterChargeThreshold + 0.6 * span,
      );
    await pumpHud(tester, game);
    expect(find.bySemanticsLabel('Charging 60 percent'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('cooldown is shown in the fire semantics', (tester) async {
    final handle = tester.ensureSemantics();
    final game = await bootHud();
    // A charged release puts the real blaster into cooldown.
    game.world.resource<Blaster>()
      ..update(
        pressed: true,
        released: false,
        canceled: false,
        held: true,
        dt: 0,
      )
      ..update(
        pressed: false,
        released: false,
        canceled: false,
        held: true,
        dt: blasterChargeThreshold + 0.2,
      )
      ..update(
        pressed: false,
        released: true,
        canceled: false,
        held: false,
        dt: 0,
      );
    await pumpHud(tester, game);
    expect(find.bySemanticsLabel('Blaster cooling down'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('ready state is shown in the fire semantics', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpHud(tester, await bootHud());
    expect(find.bySemanticsLabel('Blaster ready'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('an active shield shows the shield indicator', (tester) async {
    final game = await bootHud();
    game.world.resource<ShieldState>().activate();
    await pumpHud(tester, game);
    expect(find.byIcon(Icons.shield_rounded), findsOneWidget);
  });

  testWidgets('losing routes the HUD to the game-over panel', (tester) async {
    final game = await bootHud();
    game.world.resource<GameState>().recordLoss('You fell off the platform');
    await pumpHud(tester, game);
    expect(find.byIcon(Icons.bolt_rounded), findsOneWidget);

    game.world.setState(GameStatus.lost);
    drive(game);
    await tester.pump();

    expect(find.text('Game Over'), findsOneWidget);
    expect(find.text('You fell off the platform'), findsOneWidget);
    expect(find.byIcon(Icons.restart_alt_rounded), findsOneWidget);
    expect(
      find.byIcon(Icons.bolt_rounded),
      findsNothing,
      reason: 'the playing controls are gone on the lost screen',
    );
  });
}
