import 'package:scene_dash_v2_core/advanced.dart';
import 'package:test/test.dart';

enum GamePhase { title, overworld, dungeon }

enum PauseState { running, paused }

/// Records its name into a shared log when run.
final class RecordingAdapter implements SystemAdapter {
  final String name;
  final List<String> log;
  RecordingAdapter(this.name, this.log);

  @override
  void initialize(World world) {}

  @override
  void run() => log.add(name);
}

/// Runs an arbitrary body against the world.
final class RunAdapter implements SystemAdapter {
  final void Function(World world) body;
  RunAdapter(this.body);

  late World _world;

  @override
  void initialize(World world) => _world = world;

  @override
  void run() => body(_world);
}

void main() {
  group('addState', () {
    test('inserts CurrentState and NextState resources at the initial value',
        () {
      final app = App()..addState<GamePhase>(GamePhase.title);
      final current = app.world.resources.get<CurrentState<GamePhase>>();
      expect(current.value, GamePhase.title);
      expect(current.previous, isNull);
      expect(app.world.resources.contains<NextState<GamePhase>>(), isTrue);
    });

    test('rejects a duplicate machine for the same type', () {
      final app = App()..addState<GamePhase>(GamePhase.title);
      expect(
        () => app.addState<GamePhase>(GamePhase.overworld),
        throwsStateError,
      );
    });

    test('start throws for OnEnter systems with no covering state machine',
        () {
      final app = App()
        ..addSystemAdapter(
          RecordingAdapter('orphan', <String>[]),
          schedule: OnEnter(GamePhase.title),
          label: const SystemLabel('orphan'),
        );
      expect(app.start, throwsStateError);
    });
  });

  group('start', () {
    test('runs OnEnter(initial) after the startup schedule', () {
      final log = <String>[];
      final app = App()
        ..addState<GamePhase>(GamePhase.title)
        ..addSystemAdapter(
          RecordingAdapter('startup', log),
          schedule: Schedules.startup,
          label: const SystemLabel('startup'),
        )
        ..addSystemAdapter(
          RecordingAdapter('enter:title', log),
          schedule: OnEnter(GamePhase.title),
          label: const SystemLabel('enterTitle'),
        );
      app.start();
      expect(log, <String>['startup', 'enter:title']);
    });

    test('defers transitions queued during the initial enter', () {
      final log = <String>[];
      final app = App()..addState<GamePhase>(GamePhase.title);
      app
        ..addSystemAdapter(
          RunAdapter(
            (world) => world.resources
                .get<NextState<GamePhase>>()
                .set(GamePhase.overworld),
          ),
          schedule: OnEnter(GamePhase.title),
          label: const SystemLabel('skipTitle'),
        )
        ..addSystemAdapter(
          RecordingAdapter('enter:overworld', log),
          schedule: OnEnter(GamePhase.overworld),
          label: const SystemLabel('enterOverworld'),
        );
      app.start();
      final current = app.world.resources.get<CurrentState<GamePhase>>();
      expect(current.value, GamePhase.title);
      expect(log, isEmpty);

      app.applyStateTransitions();
      expect(current.value, GamePhase.overworld);
      expect(log, <String>['enter:overworld']);
    });
  });

  group('applyStateTransitions', () {
    test('runs OnExit(old) then OnEnter(new) and updates value/previous', () {
      final log = <String>[];
      final app = App()
        ..addState<GamePhase>(GamePhase.title)
        ..addSystemAdapter(
          RecordingAdapter('exit:title', log),
          schedule: OnExit(GamePhase.title),
          label: const SystemLabel('exitTitle'),
        )
        ..addSystemAdapter(
          RecordingAdapter('enter:overworld', log),
          schedule: OnEnter(GamePhase.overworld),
          label: const SystemLabel('enterOverworld'),
        );
      app.start();

      app.world.resources.get<NextState<GamePhase>>().set(GamePhase.overworld);
      app.applyStateTransitions();

      final current = app.world.resources.get<CurrentState<GamePhase>>();
      expect(current.value, GamePhase.overworld);
      expect(current.previous, GamePhase.title);
      expect(log, <String>['exit:title', 'enter:overworld']);
    });

    test('setting the current value is a no-op', () {
      final log = <String>[];
      final app = App()
        ..addState<GamePhase>(GamePhase.title)
        ..addSystemAdapter(
          RecordingAdapter('exit:title', log),
          schedule: OnExit(GamePhase.title),
          label: const SystemLabel('exitTitle'),
        )
        ..addSystemAdapter(
          RecordingAdapter('enter:title', log),
          schedule: OnEnter(GamePhase.title),
          label: const SystemLabel('enterTitle'),
        );
      app.start();
      log.clear(); // drop the initial enter

      app.world.resources.get<NextState<GamePhase>>().set(GamePhase.title);
      app.applyStateTransitions();

      expect(log, isEmpty);
      expect(
        app.world.resources.get<CurrentState<GamePhase>>().previous,
        isNull,
      );
    });

    test('the last set before application wins', () {
      final log = <String>[];
      final app = App()
        ..addState<GamePhase>(GamePhase.title)
        ..addSystemAdapter(
          RecordingAdapter('enter:overworld', log),
          schedule: OnEnter(GamePhase.overworld),
          label: const SystemLabel('enterOverworld'),
        )
        ..addSystemAdapter(
          RecordingAdapter('enter:dungeon', log),
          schedule: OnEnter(GamePhase.dungeon),
          label: const SystemLabel('enterDungeon'),
        );
      app.start();

      app.world.resources.get<NextState<GamePhase>>()
        ..set(GamePhase.overworld)
        ..set(GamePhase.dungeon);
      app.applyStateTransitions();

      expect(
        app.world.resources.get<CurrentState<GamePhase>>().value,
        GamePhase.dungeon,
      );
      expect(log, <String>['enter:dungeon']);
    });

    test('chained transitions settle within one call', () {
      final log = <String>[];
      final app = App()..addState<GamePhase>(GamePhase.title);
      app
        ..addSystemAdapter(
          RunAdapter(
            (world) => world.resources
                .get<NextState<GamePhase>>()
                .set(GamePhase.dungeon),
          ),
          schedule: OnEnter(GamePhase.overworld),
          label: const SystemLabel('overworldToDungeon'),
        )
        ..addSystemAdapter(
          RecordingAdapter('enter:dungeon', log),
          schedule: OnEnter(GamePhase.dungeon),
          label: const SystemLabel('enterDungeon'),
        );
      app.start();

      app.world.resources.get<NextState<GamePhase>>().set(GamePhase.overworld);
      app.applyStateTransitions();

      expect(
        app.world.resources.get<CurrentState<GamePhase>>().value,
        GamePhase.dungeon,
      );
      expect(log, <String>['enter:dungeon']);
    });

    test('a transition cycle throws instead of hanging', () {
      final app = App()..addState<GamePhase>(GamePhase.title);
      app
        ..addSystemAdapter(
          RunAdapter(
            (world) => world.resources
                .get<NextState<GamePhase>>()
                .set(GamePhase.dungeon),
          ),
          schedule: OnEnter(GamePhase.overworld),
          label: const SystemLabel('aToB'),
        )
        ..addSystemAdapter(
          RunAdapter(
            (world) => world.resources
                .get<NextState<GamePhase>>()
                .set(GamePhase.overworld),
          ),
          schedule: OnEnter(GamePhase.dungeon),
          label: const SystemLabel('bToA'),
        );
      app.start();

      app.world.resources.get<NextState<GamePhase>>().set(GamePhase.overworld);
      expect(app.applyStateTransitions, throwsStateError);
    });

    test('machines of different types transition independently', () {
      final log = <String>[];
      final app = App()
        ..addState<GamePhase>(GamePhase.overworld)
        ..addState<PauseState>(PauseState.running)
        ..addSystemAdapter(
          RecordingAdapter('enter:paused', log),
          schedule: OnEnter(PauseState.paused),
          label: const SystemLabel('enterPaused'),
        );
      app.start();

      app.world.resources.get<NextState<PauseState>>().set(PauseState.paused);
      app.applyStateTransitions();

      expect(log, <String>['enter:paused']);
      expect(
        app.world.resources.get<CurrentState<GamePhase>>().value,
        GamePhase.overworld,
      );
      expect(
        app.world.resources.get<CurrentState<PauseState>>().value,
        PauseState.paused,
      );
    });

    test('throws before start', () {
      final app = App()..addState<GamePhase>(GamePhase.title);
      expect(app.applyStateTransitions, throwsStateError);
    });
  });

  group('DespawnOnExit', () {
    Entity spawnScoped(App app, Object value) {
      final entity = app.world.entities.spawn();
      app.world
          .ensureObjectStore<DespawnOnExit>()
          .insert(entity.index, DespawnOnExit(value));
      return entity;
    }

    test('despawns entities scoped to the exited value, after OnExit runs',
        () {
      final app = App()..addState<GamePhase>(GamePhase.overworld);
      late Entity overworldScoped;
      late bool aliveDuringExit;
      app.addSystemAdapter(
        RunAdapter((world) => aliveDuringExit = world.isAlive(overworldScoped)),
        schedule: OnExit(GamePhase.overworld),
        label: const SystemLabel('exitOverworld'),
      );
      app.start();

      overworldScoped = spawnScoped(app, GamePhase.overworld);
      final dungeonScoped = spawnScoped(app, GamePhase.dungeon);
      final unscoped = app.world.entities.spawn();

      app.world.resources.get<NextState<GamePhase>>().set(GamePhase.dungeon);
      app.applyStateTransitions();

      expect(aliveDuringExit, isTrue);
      expect(app.world.isAlive(overworldScoped), isFalse);
      expect(app.world.isAlive(dungeonScoped), isTrue);
      expect(app.world.isAlive(unscoped), isTrue);
    });

    test('only the transitioning machine\'s scope is swept', () {
      final app = App()
        ..addState<GamePhase>(GamePhase.overworld)
        ..addState<PauseState>(PauseState.running);
      app.start();

      final phaseScoped = spawnScoped(app, GamePhase.overworld);

      app.world.resources.get<NextState<PauseState>>().set(PauseState.paused);
      app.applyStateTransitions();

      expect(app.world.isAlive(phaseScoped), isTrue);
    });

    test('addState registers the store, so commands.insert works untouched',
        () {
      final app = App()..addState<GamePhase>(GamePhase.overworld);
      app.start();

      final entity = app.world.entities.spawn();
      app.world.commands
          .insert<DespawnOnExit>(entity, const DespawnOnExit(GamePhase.overworld));
      app.world.commands.apply();

      app.world.resources.get<NextState<GamePhase>>().set(GamePhase.dungeon);
      app.applyStateTransitions();
      expect(app.world.isAlive(entity), isFalse);
    });

    test('sweeps each hop of a chained transition', () {
      final app = App()..addState<GamePhase>(GamePhase.title);
      late Entity titleScoped;
      late Entity overworldScoped;
      app.addSystemAdapter(
        RunAdapter((world) {
          overworldScoped = spawnScoped(app, GamePhase.overworld);
          world.resources.get<NextState<GamePhase>>().set(GamePhase.dungeon);
        }),
        schedule: OnEnter(GamePhase.overworld),
        label: const SystemLabel('passThroughOverworld'),
      );
      app.start();

      titleScoped = spawnScoped(app, GamePhase.title);
      app.world.resources.get<NextState<GamePhase>>().set(GamePhase.overworld);
      app.applyStateTransitions();

      expect(app.world.isAlive(titleScoped), isFalse);
      expect(app.world.isAlive(overworldScoped), isFalse);
      expect(
        app.world.resources.get<CurrentState<GamePhase>>().value,
        GamePhase.dungeon,
      );
    });
  });

  group('inState', () {
    test('gates a system to the matching state', () {
      final log = <String>[];
      final app = App()
        ..addState<GamePhase>(GamePhase.title)
        ..addSystemAdapter(
          RecordingAdapter('move', log),
          schedule: Schedules.update,
          label: const SystemLabel('move'),
          runIf: inState(GamePhase.overworld),
        );
      app.start();

      app.runSchedule(Schedules.update);
      expect(log, isEmpty);

      app.world.resources.get<NextState<GamePhase>>().set(GamePhase.overworld);
      app.applyStateTransitions();
      app.runSchedule(Schedules.update);
      expect(log, <String>['move']);
    });
  });
}
