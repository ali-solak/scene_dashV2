import 'package:scene_dash_v2_core/scene_dash_v2_core.dart';
import 'package:test/test.dart';

final class Shield {
  const Shield();
}

final class Other {
  const Other();
}

/// The number of fixed steps until a `removeAfter:` deadline of [duration]
/// expires, replaying the tracker's own accumulation — 1/60 is not
/// binary-exact, so boundaries must come from the same float walk the
/// tracker performs, never from `duration / dt` (the combat-suite lesson).
int ticksFor(double duration, double dt) {
  var remaining = duration;
  var ticks = 0;
  while (true) {
    remaining -= dt;
    ticks++;
    if (remaining <= 0) return ticks;
  }
}

void main() {
  const dt = 1 / 60;

  TestGame boot({List<Feature> features = const <Feature>[]}) {
    final game = TestGame.headless(
      features: [(g) => g.registerComponent<Shield>(), ...features],
    );
    game.start();
    return game;
  }

  group('removeAfter (S7)', () {
    test('removes at the exact fixed tick', () {
      const duration = 0.5;
      final ticks = ticksFor(duration, dt);
      final game = boot();
      final entity = game.world.spawn(<Object>[]);
      game.pump();

      game.world.add(entity, const Shield(), removeAfter: duration);
      expect(game.world.expiryOf<Shield>(entity), duration);

      game.pumpFixed(steps: ticks - 1);
      expect(
        game.world.has<Shield>(entity),
        isTrue,
        reason: 'alive through tick ${ticks - 1}',
      );

      game.pumpFixed(steps: 1);
      expect(
        game.world.has<Shield>(entity),
        isFalse,
        reason: 'gone after tick $ticks\'s boundary',
      );
      expect(game.world.expiryOf<Shield>(entity), isNull);
    });

    test('a paused clock stalls expiry', () {
      final game = boot();
      final entity = game.world.spawn(<Object>[]);
      game.pump();
      game.world.add(entity, const Shield(), removeAfter: 4 * dt);

      game.clock.paused = true;
      game.pumpFixed(steps: 30);
      expect(game.world.has<Shield>(entity), isTrue);
      expect(
        game.world.expiryOf<Shield>(entity),
        4 * dt,
        reason: 'no fixed step ran, so nothing was consumed',
      );

      game.clock.paused = false;
      game.pumpFixed(steps: ticksFor(4 * dt, dt));
      expect(game.world.has<Shield>(entity), isFalse);
    });

    test('hitstop does not consume the duration', () {
      final game = boot();
      final entity = game.world.spawn(<Object>[]);
      game.pump();
      game.world.add(entity, const Shield(), removeAfter: 4 * dt);

      // 4.5 frames of freeze: the scale is read before the freeze is
      // served, so all five pumps land frozen and run no fixed step.
      game.clock.freezeFor(4.5 * dt);
      game.pumpFixed(steps: 5);
      expect(game.world.expiryOf<Shield>(entity), 4 * dt);

      game.pumpFixed(steps: ticksFor(4 * dt, dt));
      expect(game.world.has<Shield>(entity), isFalse);
    });

    test('re-adding refreshes the deadline (S4)', () {
      const duration = 10 * dt;
      final ticks = ticksFor(duration, dt);
      final game = boot();
      final entity = game.world.spawn(<Object>[]);
      game.pump();

      game.world.add(entity, const Shield(), removeAfter: duration);
      game.pumpFixed(steps: ticks - 2);
      game.world.add(entity, const Shield(), removeAfter: duration);
      expect(game.world.expiryOf<Shield>(entity), duration);

      game.pumpFixed(steps: ticks - 1);
      expect(
        game.world.has<Shield>(entity),
        isTrue,
        reason: 'the refresh restarted the countdown',
      );
      game.pumpFixed(steps: 1);
      expect(game.world.has<Shield>(entity), isFalse);
    });

    test('re-adding without removeAfter cancels the deadline '
        '(latest add wins)', () {
      final game = boot();
      final entity = game.world.spawn(<Object>[]);
      game.pump();

      game.world.add(entity, const Shield(), removeAfter: 4 * dt);
      game.world.add(entity, const Shield());
      expect(game.world.expiryOf<Shield>(entity), isNull);

      game.pumpFixed(steps: 30);
      expect(
        game.world.has<Shield>(entity),
        isTrue,
        reason: 'the latest add carried no lifetime',
      );
    });

    test('manual remove cancels the tracker', () {
      final game = boot();
      final entity = game.world.spawn(<Object>[]);
      game.pump();

      game.world.add(entity, const Shield(), removeAfter: 10 * dt);
      game.pumpFixed(steps: 2);
      game.world.remove<Shield>(entity);
      expect(game.world.expiryOf<Shield>(entity), isNull);
      game.pump();

      // A plain re-add after the cancel stays permanent.
      game.world.add(entity, const Shield());
      game.pumpFixed(steps: 30);
      expect(game.world.has<Shield>(entity), isTrue);
    });

    test('despawn invalidates the deadline; a reused slot is untouched', () {
      final game = boot();
      final doomed = game.world.spawn(<Object>[]);
      game.pump();
      game.world.add(doomed, const Shield(), removeAfter: 6 * dt);
      game.world.despawn(doomed);
      game.pump();

      // Reuse the freed slot with a fresh entity carrying the same type.
      final reused = game.world.spawn([const Shield()]);
      game.pump();
      expect(
        reused.index,
        doomed.index,
        reason: 'the test needs the slot actually reused',
      );
      expect(game.world.expiryOf<Shield>(reused), isNull);

      game.pumpFixed(steps: 30);
      expect(
        game.world.has<Shield>(reused),
        isTrue,
        reason: 'the stale deadline must not remove from the reused slot',
      );
    });

    test('expiryOf counts down per fixed step and is null when untracked', () {
      final game = boot();
      final entity = game.world.spawn([const Shield(), const Other()]);
      game.pump();
      expect(
        game.world.expiryOf<Shield>(entity),
        isNull,
        reason: 'spawned without removeAfter',
      );

      game.world.add(entity, const Shield(), removeAfter: 10 * dt);
      game.pumpFixed(steps: 3);
      expect(game.world.expiryOf<Shield>(entity), closeTo(7 * dt, 1e-12));
      expect(game.world.expiryOf<Other>(entity), isNull);
    });

    test('expiry fires onRemove observers', () {
      Shield? removed;
      final game = boot(
        features: [
          (g) => g.observe<Shield>(
            onRemove: (world, entity, shield) => removed = shield,
          ),
        ],
      );
      final entity = game.world.spawn(<Object>[]);
      game.pump();

      const shield = Shield();
      game.world.add(entity, shield, removeAfter: 4 * dt);
      game.pumpFixed(steps: ticksFor(4 * dt, dt));
      expect(identical(removed, shield), isTrue);
    });
  });

  group('world.single / singleOrNull (S9)', () {
    test('single returns the sole component unwrapped', () {
      final game = boot();
      game.world.spawn([const Shield()]);
      game.pump();
      expect(game.world.single<Shield>(), isA<Shield>());
    });

    test('single throws with the count on zero and on several', () {
      final game = boot();
      expect(
        game.world.single<Shield>,
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('found 0'),
          ),
        ),
      );
      game.world.spawn([const Shield()]);
      game.world.spawn([const Shield()]);
      game.pump();
      expect(
        game.world.single<Shield>,
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('found 2'),
          ),
        ),
      );
    });

    test('singleOrNull returns null on zero, still throws on several', () {
      final game = boot();
      expect(game.world.singleOrNull<Shield>(), isNull);
      game.world.spawn([const Shield()]);
      game.pump();
      expect(game.world.singleOrNull<Shield>(), isA<Shield>());
      game.world.spawn([const Shield()]);
      game.pump();
      expect(game.world.singleOrNull<Shield>, throwsStateError);
    });
  });
}
