import 'package:flutter_test/flutter_test.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';
import 'package:scene_game/collectables/collectables.dart';
import 'package:scene_game/decor/decor.dart';
import 'package:scene_game/game/camera_rig.dart';
import 'package:scene_game/game/game_state.dart';
import 'package:scene_game/game/sets.dart';
import 'package:scene_game/hud/debug_panel.dart';
import 'package:scene_game/player/player.dart';
import 'package:scene_game/projectiles/projectiles.dart';
import 'package:scene_game/rocks/rocks.dart';
import 'package:scene_game/rules/rules.dart';
import 'package:scene_game/world/world.dart';

/// The whole-build acceptance row "conflict detector clean at `throw` with
/// `strictAccess` for the validation game": every system registration in
/// the full feature set declares its access, and no unordered pair
/// conflicts. `TestGame` already defaults the conflict policy to error;
/// `strictAccess: true` additionally rejects undeclared registrations —
/// both fire at boot, so reaching the started state *is* the assertion.
void main() {
  test('the full feature set boots clean under strictAccess + throw', () {
    final game = TestGame.headless(
      strictAccess: true,
      features: [
        (game) {
          game
            ..addState<GameStatus>(GameStatus.playing)
            ..configureSets(Schedules.fixedUpdate, [
              GameSets.movement,
              GameSets.actions,
            ])
            ..configureSets(
                Schedules.update, [GameSets.logic, GameSets.rules])
            ..world.insert(ButtonInput<GameAction>())
            ..world.insert(CameraRig())
            ..world.insert(FpsCounter())
            ..world.insert(DebugCubit())
            ..addSystem(Schedules.frameStart, applyDebugSettings,
                reads: const {});
        },
        installGizmos(enabled: false),
        installWorldGeometry,
        installPlayer,
        installProjectiles,
        installRocks,
        installCollectables,
        installRules,
        installDecor,
      ],
    );

    game.start(); // strictAccess + conflict detection both fire here
    expect(game.world.state<GameStatus>(), GameStatus.playing);
  });
}
