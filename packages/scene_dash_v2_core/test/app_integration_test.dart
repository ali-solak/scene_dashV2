import 'package:scene_dash_v2_core/advanced.dart';
import 'package:test/test.dart';

// --- Components ---

final class Position {
  double x;
  double y;
  Position(this.x, this.y);
}

final class Velocity {
  final double x;
  final double y;
  const Velocity(this.x, this.y);
}

final class Player {
  const Player();
}

// --- Event ---

final class PlayerSpawned {
  final Entity entity;
  const PlayerSpawned(this.entity);
}

// --- Hand-written system adapters (stand-ins for generated code) ---

final class SpawnPlayerAdapter implements SystemAdapter {
  late final Commands _commands;
  late final EventWriter<PlayerSpawned> _spawned;

  @override
  void initialize(World world) {
    _commands = world.commands;
    _spawned = world.eventChannel<PlayerSpawned>().writer();
  }

  @override
  void run() {
    final entity = _commands.spawn().entity;
    _commands
      ..insert<Position>(entity, Position(0, 0))
      ..insert<Velocity>(entity, const Velocity(1, 2))
      ..insert<Player>(entity, const Player());
    _spawned.send(PlayerSpawned(entity));
  }
}

final class MovePlayerAdapter implements SystemAdapter {
  late final Query2<Position, Velocity> _players;
  late final FixedTime _time;

  @override
  void initialize(World world) {
    _players = world.query2<Position, Velocity>(withTypes: const [Player]);
    _time = world.resources.get<FixedTime>();
  }

  @override
  void run() {
    _players.each((entity, position, velocity) {
      position
        ..x += velocity.x * _time.delta
        ..y += velocity.y * _time.delta;
    });
  }
}

// --- Plugins ---

final class DemoPlugin extends Plugin {
  const DemoPlugin();

  @override
  void build(AppBuilder app) {
    app
      ..addEvent<PlayerSpawned>()
      ..insertResource<FixedTime>(FixedTime()..delta = 0.5)
      ..addSystemAdapter(
        SpawnPlayerAdapter(),
        schedule: Schedules.startup,
        label: const SystemLabel('demo.spawn'),
      )
      ..addSystemAdapter(
        MovePlayerAdapter(),
        schedule: Schedules.update,
        label: const SystemLabel('demo.move'),
      );
  }
}

final class ConfiguredPlugin extends Plugin {
  final int config;
  ConfiguredPlugin(this.config);

  @override
  void build(AppBuilder app) {}
}

final class NeedsDemoPlugin extends Plugin {
  const NeedsDemoPlugin();

  @override
  List<Type> get dependencies => const [DemoPlugin];

  @override
  void build(AppBuilder app) {}
}

App _appWithStores() {
  final app = App();
  app.world.stores
    ..register<Position>(ObjectComponentStore<Position>())
    ..register<Velocity>(ObjectComponentStore<Velocity>())
    ..register<Player>(TagStore());
  return app;
}

void main() {
  group('App integration (no code generation)', () {
    test(
      'startup spawns, deferred commands apply, update integrates motion',
      () {
        final app = _appWithStores()..addPlugin(const DemoPlugin());
        app.start(); // runs startup; spawn commands flushed afterwards

        // After startup, exactly one player exists at the origin.
        final afterStartup = <Position>[];
        app.world.query1<Position>().each((e, p) => afterStartup.add(p));
        expect(afterStartup, hasLength(1));
        expect(afterStartup.single.x, 0);

        app.runSchedule(Schedules.update);

        final moved = <Position>[];
        app.world.query1<Position>().each((e, p) => moved.add(p));
        expect(moved.single.x, closeTo(0.5, 1e-9));
        expect(moved.single.y, closeTo(1.0, 1e-9));

        app.runSchedule(Schedules.update);
        final moved2 = <Position>[];
        app.world.query1<Position>().each((e, p) => moved2.add(p));
        expect(moved2.single.x, closeTo(1.0, 1e-9));
      },
    );

    test('plugin dependencies are validated', () {
      final missing = _appWithStores();
      expect(
        () => missing.addPlugin(const NeedsDemoPlugin()),
        throwsStateError,
      );

      final satisfied = _appWithStores()
        ..addPlugin(const DemoPlugin())
        ..addPlugin(const NeedsDemoPlugin());
      expect(satisfied.start, returnsNormally);
    });

    test('re-adding the same plugin instance is a no-op', () {
      final app = _appWithStores()
        ..addPlugin(const DemoPlugin())
        ..addPlugin(const DemoPlugin()); // const-canonicalized: same instance
      // Only one spawn system registered → only one player after startup.
      app.start();
      var count = 0;
      app.world.query1<Position>().each((e, p) => count++);
      expect(count, 1);
    });

    test('adding a different instance of the same plugin type throws', () {
      final app = _appWithStores()..addPlugin(ConfiguredPlugin(1));
      // A second, differently-configured instance would be silently discarded
      // if it were treated as a duplicate no-op — fail loudly instead.
      expect(() => app.addPlugin(ConfiguredPlugin(2)), throwsStateError);
    });
  });
}
