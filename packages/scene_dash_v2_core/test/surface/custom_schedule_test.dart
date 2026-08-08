import 'package:scene_dash_v2_core/scene_dash_v2_core.dart';
import 'package:test/test.dart';

abstract final class TurnSchedules {
  static const resolve = ScheduleLabel('battle.resolve');
  static const cleanup = ScheduleLabel('battle.cleanup');
}

abstract final class TurnSets {
  static const damage = SystemSet('battle.damage');
  static const death = SystemSet('battle.death');
}

enum Phase { menu, battle }

final class Turn {
  int number = 0;
}

final class Log {
  final lines = <String>[];
}

void main() {
  group('custom schedules', () {
    test('a custom schedule never runs on its own; runSchedule runs it once '
        'per call', () {
      final log = <String>[];
      void resolveTurn(World world) => log.add('resolve');

      final game = TestGame.headless(
        features: [
          (game) => game
            ..addSchedule(TurnSchedules.resolve)
            ..addSystem(TurnSchedules.resolve, resolveTurn, reads: const {}),
        ],
      )..start();

      game.pump();
      game.pumpFixed(steps: 4);
      expect(log, isEmpty, reason: 'no frame drives a custom schedule');

      game.world.runSchedule(TurnSchedules.resolve);
      game.world.runSchedule(TurnSchedules.resolve);
      expect(log, ['resolve', 'resolve']);
    });

    test('ordering, sets and run conditions work as in a built-in '
        'schedule', () {
      final log = <String>[];
      void applyDamage(World world) => log.add('damage');
      void clearDead(World world) => log.add('death');
      void onlyInBattle(World world) => log.add('battle');

      final game = TestGame.headless(
        features: [
          (game) => game
            ..addState<Phase>(Phase.menu)
            ..addSchedule(TurnSchedules.resolve)
            ..configureSets(TurnSchedules.resolve, [
              TurnSets.damage,
              TurnSets.death,
            ])
            // Registered later, ordered earlier by its set.
            ..addSystem(
              TurnSchedules.resolve,
              clearDead,
              reads: const {},
              inSet: TurnSets.death,
            )
            ..addSystem(
              TurnSchedules.resolve,
              applyDamage,
              reads: const {},
              inSet: TurnSets.damage,
            )
            ..addSystem(
              TurnSchedules.resolve,
              onlyInBattle,
              reads: const {},
              runIf: inState(Phase.battle),
            ),
        ],
      )..start();

      game.world.runSchedule(TurnSchedules.resolve);
      expect(log, ['damage', 'death']);

      game.world.setState(Phase.battle);
      game.pump();
      log.clear();
      game.world.runSchedule(TurnSchedules.resolve);
      expect(log, ['damage', 'death', 'battle']);
    });

    test('a system can drive another schedule inline', () {
      final log = <String>[];
      void endTurn(World world) {
        world.resource<Turn>().number += 1;
        world.runSchedule(TurnSchedules.cleanup);
        log.add('endTurn');
      }

      void sweep(World world) =>
          log.add('sweep ${world.resource<Turn>().number}');

      final game = TestGame.headless(
        features: [
          (game) => game
            ..world.insert(Turn())
            ..addSchedule(TurnSchedules.cleanup)
            ..addSystem(TurnSchedules.cleanup, sweep, reads: const {})
            ..addSystem(Schedules.update, endTurn, reads: const {}),
        ],
      )..start();

      game.pump();
      // The nested schedule completes before its caller does.
      expect(log, ['sweep 1', 'endTurn']);
    });

    test('a run is a full command boundary: back-to-back runs compose', () {
      void reinforce(World world) => world.spawn([Turn()]);
      void countTroops(World world) => world.resource<Log>().lines.add(
        'troops ${world.query<Turn>().count()}',
      );

      final game = TestGame.headless(
        features: [
          (game) => game
            ..world.insert(Log())
            ..registerComponent<Turn>()
            ..addSchedule(TurnSchedules.resolve)
            ..addSchedule(TurnSchedules.cleanup)
            ..addSystem(TurnSchedules.resolve, reinforce, writes: {Turn})
            ..addSystem(TurnSchedules.cleanup, countTroops, reads: {Turn}),
        ],
      );

      game.runSchedule(TurnSchedules.resolve);
      // Spawns settle with the run, not at the next frame: the second
      // schedule sees what the first spawned.
      expect(game.world.query<Turn>().count(), 1);
      game.runSchedule(TurnSchedules.cleanup);
      expect(game.world.resource<Log>().lines, ['troops 1']);
    });

    test('a run settles commands but not state transitions', () {
      void endBattle(World world) => world.setState(Phase.menu);

      final game = TestGame.headless(
        features: [
          (game) => game
            ..addState<Phase>(Phase.battle)
            ..addSchedule(TurnSchedules.resolve)
            ..addSystem(TurnSchedules.resolve, endBattle, reads: const {}),
        ],
      );

      game.runSchedule(TurnSchedules.resolve);
      // OnExit/OnEnter stay with the frame: a run never buries them.
      expect(game.world.state<Phase>(), Phase.battle);
      game.pump();
      expect(game.world.state<Phase>(), Phase.menu);
    });

    test('nesting is allowed; a cycle throws instead of overflowing', () {
      void bounce(World world) => world.runSchedule(TurnSchedules.resolve);

      final game = TestGame.headless(
        features: [
          (game) => game
            ..addSchedule(TurnSchedules.resolve)
            ..addSystem(TurnSchedules.resolve, bounce, reads: const {}),
        ],
      );

      expect(
        () => game.runSchedule(TurnSchedules.resolve),
        throwsA(
          isStateError.having(
            (e) => e.message,
            'message',
            allOf(contains('Recursive'), contains('battle.resolve')),
          ),
        ),
      );
    });

    test('the surface runs custom labels only', () {
      final game = TestGame.headless()..start();
      for (final label in [Schedules.update, Schedules.shutdown]) {
        expect(
          () => game.world.runSchedule(label),
          throwsA(
            isStateError.having(
              (e) => e.message,
              'message',
              contains('framework schedule'),
            ),
          ),
          reason: '${label.id} belongs to the frame driver',
        );
      }
      expect(
        () => game.world.runSchedule(OnEnter(Phase.battle)),
        throwsStateError,
      );
    });

    test('an unregistered schedule label throws', () {
      final game = TestGame.headless()..start();
      expect(
        () => game.world.runSchedule(TurnSchedules.resolve),
        throwsStateError,
      );
    });
  });
}
