import 'package:headless_example/game.dart';
import 'package:scene_dash_v2_core/scene_dash_v2_core.dart';
import 'package:test/test.dart';

void main() {
  test('the race plays out frame-exactly on TestGame', () {
    // 0.25 s fixed steps: velocity (1, 2) moves the player 0.25/0.5 per
    // step, the finish line (x >= 1) falls exactly on step 4, the boost's
    // 0.4 s lifetime expires during frame 2, and the every(0.5) cadence
    // fires on steps 2 and 4.
    final game = TestGame.headless(fixedDt: 0.25, features: [installRace]);
    game.start();

    final race = game.world.resource<RaceState>();

    // Frame 1: startup spawned the run; the first fixed step integrates
    // motion and the referee hears the spawn event.
    game.pumpFixed(steps: 1);
    final (player, position) = game.world.query<Position>().single;
    expect(position.x, 0.25);
    expect(position.y, 0.5);
    expect(game.world.has<PlayerMarker>(player), isTrue);
    expect(race.spawnsSeen, 1);
    expect(race.boostAvailable, isTrue);
    expect(race.statusReports, 0);
    expect(race.winner, isNull);

    // Frame 2: the every(0.5) cadence completes its first period, and the
    // boost's DespawnAfter (0.4 s of frame time) expires at the frame's
    // update phase — after the fixed-phase referee snapshotted it.
    game.pumpFixed(steps: 1);
    expect(position.x, 0.5, reason: 'stable reference writes through');
    expect(race.statusReports, 1);
    expect(game.world.entitiesWith(require: [BoostMarker]).count(), 0);

    // Frames 3-4: the referee now sees the boost gone; x reaches the
    // finish line on step 4 and the referee (after move) records the
    // winner the same step.
    game.pumpFixed(steps: 1);
    expect(race.boostAvailable, isFalse);
    expect(race.winner, isNull);
    game.pumpFixed(steps: 1);
    expect(position.x, 1.0);
    expect(race.winner, player);
    expect(race.statusReports, 2);
  });

  test('identical runs are identical (determinism)', () {
    (double, int, int) run() {
      final game = TestGame.headless(fixedDt: 0.25, features: [installRace]);
      game.pumpFixed(steps: 10);
      final race = game.world.resource<RaceState>();
      final position = game.world.query<Position>().single.$2;
      return (position.x, race.statusReports, race.spawnsSeen);
    }

    expect(run(), run());
  });
}
