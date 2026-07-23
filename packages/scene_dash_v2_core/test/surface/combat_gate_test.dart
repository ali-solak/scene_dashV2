/// The Phase 1 gate: a combat-grade timing feature — i-frame windows,
/// hitstop, input-buffer expiry — written entirely against the Part 1
/// surface and proven frame-exact headlessly.
///
/// A 1/64 s fixed step makes distances exact binary floats, so assertions
/// are `==`, not `closeTo`.
library;

import 'package:scene_dash_v2_core/scene_dash_v2_core.dart';
import 'package:test/test.dart';

enum CombatAction { right, strike, roll }

enum RunMode { playing }

final class Fighter {
  double x = 0;
  int stepsSeen = 0;
  int iFrames = 0;
  bool rollLatch = false;
  int hitsTaken = 0;
  int strikesLanded = 0;

  bool get iFramed => iFrames > 0;
}

final class HitLanded {
  final Entity target;
  const HitLanded(this.target);
}

const double speed = 64;
const int rollWindow = 18;
const double hitstop = 3 / 64;

/// Movement, i-frames and buffered strikes, one fixed step at a time.
void fighterSystem(World world) {
  final input = world.resource<ButtonInput<CombatAction>>();
  final buffer = world.resource<InputBuffer<CombatAction>>();
  final dt = world.resource<FixedTime>().delta;
  world.query<Fighter>().each((entity, fighter) {
    fighter.stepsSeen++;
    if (fighter.iFrames > 0) fighter.iFrames--;

    fighter.x += (input.pressed(CombatAction.right) ? 1 : 0) * speed * dt;

    final rollHeld = input.pressed(CombatAction.roll);
    if (rollHeld && !fighter.rollLatch && fighter.iFrames == 0) {
      fighter.iFrames = rollWindow;
      fighter.rollLatch = true;
    }
    if (!rollHeld) fighter.rollLatch = false;

    // A strike buffered during hitstop lands the moment the fighter can
    // act again; a stale buffer entry expires instead of firing late.
    if (buffer.consume(CombatAction.strike)) {
      fighter.strikesLanded++;
      world.emit(HitLanded(entity));
    }
  });
}

/// Applies hits: i-frames ignore them; a landed hit costs health-less
/// damage here and freezes the clock (hitstop).
void applyHits(World world) {
  for (final hit in world.events<HitLanded>()) {
    final fighter = world.tryGet<Fighter>(hit.target);
    if (fighter == null || fighter.iFramed) continue;
    fighter.hitsTaken++;
    world.resource<GameClock>().freezeFor(hitstop);
  }
}

/// The buffer ages on wall time, so hitstop cannot extend it.

void installCombat(GameBuilder game) {
  game.world
    ..insert(ButtonInput<CombatAction>())
    ..insert(InputBuffer<CombatAction>(window: 6 / 64));
  game
    ..addState(RunMode.playing)
    ..addSystem(
      Schedules.fixedUpdate,
      fighterSystem,
      writes: {Fighter},
      runIf: inState(RunMode.playing),
    )
    ..addSystem(
      Schedules.fixedUpdate,
      applyHits,
      writes: {Fighter},
      after: [fighterSystem],
    );
}

TestGame boot() {
  final game = TestGame.headless(fixedDt: 1 / 64, features: [installCombat]);
  game.world.spawn([Fighter()]);
  game.start();
  return game;
}

Fighter fighterOf(TestGame game) => game.world.query<Fighter>().single.$2;

void main() {
  test('movement integrates exactly: 60 held steps of 64 u/s at 1/64 s is '
      'exactly 60 units', () {
    final game = boot();
    game.press(CombatAction.right);
    game.pumpFixed(steps: 60);
    final fighter = fighterOf(game);
    expect(fighter.x, 60.0);
    expect(fighter.stepsSeen, 60);
  });

  test('roll i-frames last exactly 18 fixed steps', () {
    final game = boot();
    game.press(CombatAction.roll);
    game.pumpFixed(steps: 1);
    game.release(CombatAction.roll);
    final fighter = fighterOf(game);
    expect(fighter.iFramed, isTrue);
    game.pumpFixed(steps: 17);
    expect(fighter.iFramed, isTrue, reason: 'step 18 of the window');
    game.pumpFixed(steps: 1);
    expect(fighter.iFramed, isFalse, reason: 'window over, frame-exact');
  });

  test('a hit during i-frames is ignored; after them it lands and stops '
      'the clock for exactly three frames', () {
    final game = boot();
    final fighter = fighterOf(game);
    game.press(CombatAction.roll);
    game.pumpFixed(steps: 1);
    game.release(CombatAction.roll);
    game.emit(HitLanded(game.world.query<Fighter>().single.$1));
    game.pumpFixed(steps: 1); // delivered while iFramed: ignored
    expect(fighter.hitsTaken, 0);

    game.pumpFixed(steps: 17); // i-frames over
    game.press(CombatAction.right);
    game.emit(HitLanded(game.world.query<Fighter>().single.$1));
    // The hit lands on this step (freeze starts after the frame's scale
    // was read), then three frozen frames run no fixed steps.
    game.pumpFixed(steps: 1);
    expect(fighter.hitsTaken, 1);
    final stepsAtHit = fighter.stepsSeen;
    final xAtHit = fighter.x;
    game.pumpFixed(steps: 3);
    expect(fighter.stepsSeen, stepsAtHit, reason: 'hitstop: no steps');
    expect(fighter.x, xAtHit);
    expect(game.clock.freezeRemaining, 0);
    game.pumpFixed(steps: 2);
    expect(fighter.stepsSeen, stepsAtHit + 2, reason: 'resumes exactly');
  });

  test('a strike buffered during hitstop fires on the first live step; a '
      'stale one expires', () {
    final game = boot();
    final fighter = fighterOf(game);
    // Land a hit to start hitstop.
    game.emit(HitLanded(game.world.query<Fighter>().single.$1));
    game.pumpFixed(steps: 1);
    expect(fighter.hitsTaken, 1);
    // Press strike during the freeze: buffered (wall-time window 6/64).
    game.world.resource<InputBuffer<CombatAction>>().record(
      CombatAction.strike,
    );
    game.pumpFixed(steps: 3); // frozen frames
    expect(fighter.strikesLanded, 0);
    game.pumpFixed(steps: 1); // first live step: buffered strike fires
    expect(fighter.strikesLanded, 1);

    // A press left to age past the window fires nothing.
    game.world.resource<InputBuffer<CombatAction>>().record(
      CombatAction.strike,
    );
    game.clock.paused = true; // fixed steps stop; wall time keeps aging
    game.pumpFixed(steps: 8); // 8/64 wall seconds > 6/64 window
    game.clock.paused = false;
    game.pumpFixed(steps: 1);
    expect(fighter.strikesLanded, 1, reason: 'stale buffer expired');
  });

  test('determinism: identical spawns + identical inputs give identical '
      'runs', () {
    (double, int, int, int) run() {
      final game = boot();
      final fighter = fighterOf(game);
      game.press(CombatAction.right);
      game.pumpFixed(steps: 7);
      game.press(CombatAction.roll);
      game.pumpFixed(steps: 2);
      game.release(CombatAction.roll);
      game.emit(HitLanded(game.world.query<Fighter>().single.$1));
      game.pumpFixed(steps: 25);
      game.emit(HitLanded(game.world.query<Fighter>().single.$1));
      game.pumpFixed(steps: 30);
      return (fighter.x, fighter.stepsSeen, fighter.iFrames, fighter.hitsTaken);
    }

    expect(run(), run());
  });
}
