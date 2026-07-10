import 'package:flutter_scene/scene.dart' show Node;
import 'package:flutter_test/flutter_test.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';
import 'package:scene_game/collectables/collectables.dart';
import 'package:scene_game/collectables/data/config.dart';
import 'package:scene_game/game/game_state.dart';
import 'package:scene_game/game/sets.dart';
import 'package:scene_game/player/player.dart' show Player;

/// The full [Shielded] lifecycle, headless, through the real collectables
/// feature: pickup → observers fire (the bubble signal) → the damage gate
/// holds → the `removeAfter:` deadline expires frame-exactly → observers
/// fire again, damage lands. Proves S1 (observers at the flush), S4
/// (re-pickup refreshes, no re-fire) and S7 (fixed-step expiry) end to
/// end. The feature's own VFX observers no-op here (no GPU, so no
/// `PlayerShieldVisuals`); the probe pair below records the same lifecycle
/// the bubble follows.
void main() {
  const dt = 1 / 60;

  /// Fixed steps until a removeAfter of [duration] expires, replaying the
  /// tracker's own float walk (1/60 is not binary-exact).
  int ticksFor(double duration) {
    var remaining = duration;
    var ticks = 0;
    while (true) {
      remaining -= dt;
      ticks++;
      if (remaining <= 0) return ticks;
    }
  }

  ({TestGame game, Entity player, List<String> bubble}) boot() {
    final bubble = <String>[];
    final game = TestGame.headless(
      strictAccess: true,
      features: [
        (g) {
          g.addState<GameStatus>(GameStatus.playing);
          g.configureSets(Schedules.update, [GameSets.logic, GameSets.rules]);
          g.registerTag<Player>();
          // The probe pair: registered alongside the feature's VFX pair,
          // firing in registration order on the same lifecycle.
          g.observe<Shielded>(
            onAdd: (world, entity, shielded) => bubble.add('shown'),
            onRemove: (world, entity, shielded) => bubble.add('hidden'),
          );
        },
        installCollectables,
      ],
    );
    game.start();
    // A player stand-in at the origin — no GPU-bound visuals needed for
    // the lifecycle itself.
    final player = game.world.spawn([const Player(), SceneNode(Node())]);
    game.pump();
    return (game: game, player: player, bubble: bubble);
  }

  /// A pickup resting exactly on the player, so the next collection pass
  /// grabs it.
  void spawnPickupAtPlayer(TestGame game) {
    game.world.spawn([
      const Collectable(),
      const ShieldPickup(),
      SceneNode(Node()),
    ]);
  }

  test('pickup → shielded, bubble shown, damage blocked', () {
    final g = boot();
    expect(g.game.world.has<Shielded>(g.player), isFalse);

    spawnPickupAtPlayer(g.game);
    g.game.pump(); // pickup lands at frame start, collected during update
    expect(g.game.world.has<Shielded>(g.player), isTrue);
    expect(g.game.world.expiryOf<Shielded>(g.player), shieldDuration);
    expect(g.bubble, ['shown']);
    // The damage gate is exactly this check (evaluateGameRules deflects
    // instead of shoving while it holds).
    expect(g.game.world.has<Shielded>(g.player), isTrue);
  });

  test('the deadline expires frame-exactly: bubble hidden, damage lands',
      () {
    final g = boot();
    spawnPickupAtPlayer(g.game);
    g.game.pump();

    final ticks = ticksFor(shieldDuration);
    g.game.pumpFixed(steps: ticks - 1);
    expect(g.game.world.has<Shielded>(g.player), isTrue,
        reason: 'shielded through tick ${ticks - 1}');

    g.game.pumpFixed(steps: 1);
    expect(g.game.world.has<Shielded>(g.player), isFalse,
        reason: 'expired at tick $ticks — damage lands again');
    expect(g.game.world.expiryOf<Shielded>(g.player), isNull);
    expect(g.bubble, ['shown', 'hidden']);
  });

  test('re-pickup while shielded refreshes the deadline and fires nothing',
      () {
    final g = boot();
    spawnPickupAtPlayer(g.game);
    g.game.pump();
    g.game.pumpFixed(steps: 30); // consume half a second

    spawnPickupAtPlayer(g.game);
    g.game.pump();
    expect(g.game.world.expiryOf<Shielded>(g.player), shieldDuration,
        reason: 'back to full duration');
    expect(g.bubble, ['shown'], reason: 'S4: add-over-existing is silent');
  });

  test('a run restart removes a carried shield through the same observers',
      () {
    final g = boot();
    spawnPickupAtPlayer(g.game);
    g.game.pump();
    expect(g.game.world.has<Shielded>(g.player), isTrue);

    g.game.world.setState(GameStatus.lost);
    g.game.pump();
    g.game.world.setState(GameStatus.playing);
    g.game.pump();
    expect(g.game.world.has<Shielded>(g.player), isFalse);
    expect(g.bubble, ['shown', 'hidden']);
  });
}
