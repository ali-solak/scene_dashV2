import 'package:scene_dash_v2_core/advanced.dart'
    show StoreChangeListener, TagStore;
import 'package:scene_dash_v2_core/scene_dash_v2_core.dart';
import 'package:test/test.dart';

class Position {
  Position(this.x);
  final int x;
}

final class SpecialPosition extends Position {
  SpecialPosition(super.x);
}

final class Recorder implements StoreChangeListener {
  final List<int> rows = <int>[];

  @override
  void rowChanged(int entityIndex) => rows.add(entityIndex);

  @override
  void cleared() => rows.add(-1);
}

final class Brawler {
  Brawler(this.power);
  final int power;
}

final class Player {}

final class Enemy {}

final class Stunned implements Tag {}

sealed class GameEvent {}

final class EnemyKilled extends GameEvent {}

final class WaveCleared extends GameEvent {}

void main() {
  test('get, tryGet and has see a part no query has named yet', () {
    final game = TestGame.headless();
    final entity = game.world.spawn([Brawler(3)]);
    game.start();
    expect(game.world.has<Brawler>(entity), isTrue);
    expect(game.world.tryGet<Brawler>(entity)?.power, 3);
    expect(game.world.get<Brawler>(entity).power, 3);
  });

  test('has on an unregistered tag is false and creates no store', () {
    final game = TestGame.headless();
    final entity = game.world.spawn([Brawler(1)]);
    game.start();
    expect(game.world.has<Stunned>(entity), isFalse);
    expect(game.world.stores.isRegistered(Stunned), isFalse);
  });

  test('having and without filter by type, creating their stores', () {
    final game = TestGame.headless();
    final stunned = game.world.spawn([Brawler(1), Stunned()]);
    game.world
      ..spawn([Brawler(2), Enemy()])
      ..spawn([Brawler(3)]);
    game.start();
    final brawlers = game.world.query<Brawler>();
    expect(brawlers.having<Stunned>().single.$1, stunned);
    expect(brawlers.having<Enemy>().single.$2.power, 2);
    expect(brawlers.without<Stunned>().without<Enemy>().single.$2.power, 3);
    expect(brawlers.having<Player>().isEmpty, isTrue);
    expect(brawlers.count(), 3);
  });

  test('first typed use inside a running query claims without asserting', () {
    final seen = <Player>[];
    final game = TestGame.headless(
      features: [
        (g) => g.addSystem(Schedules.update, (World world) {
          world.query<Enemy>().each((entity, enemy) {
            seen.add(world.single<Player>());
          });
        }),
      ],
    );
    final player = Player();
    game.world
      ..spawn([Enemy()])
      ..spawn([player]);
    game.start();
    game.pump();
    expect(seen, [same(player)]);
  });

  test('emit prefers the event class channel, else the emitted type', () {
    final base = <GameEvent>[];
    final exact = <EnemyKilled>[];
    final game = TestGame.headless(
      features: [
        (g) => g.addSystem(Schedules.update, (World world) {
          base.addAll(world.events<GameEvent>());
          exact.addAll(world.events<EnemyKilled>());
        }),
      ],
    );
    game.start();
    game
      ..emit<GameEvent>(EnemyKilled())
      ..emit<GameEvent>(WaveCleared())
      ..emit(EnemyKilled());
    game.pump();
    expect(base, [isA<EnemyKilled>(), isA<WaveCleared>()]);
    expect(exact, hasLength(1));
  });

  test('spawn rejects types, tear-offs, futures and nested lists', () {
    final world = TestGame.headless().world;
    for (final part in <Object>[
      Enemy,
      Enemy.new,
      Future<void>.value(),
      [Enemy()],
    ]) {
      expect(() => world.spawn([part]), throwsArgumentError);
    }
  });

  test('subtype lookups read the supertype store without splitting it', () {
    final game = TestGame.headless();
    game.start();
    expect(game.world.query<Position>().count(), 0);
    final first = game.world.spawn([SpecialPosition(1)]);
    game.pump();
    expect(game.world.tryGet<SpecialPosition>(first)?.x, 1);
    expect(game.world.has<SpecialPosition>(first), isTrue);
    expect(game.world.stores.isRegistered(SpecialPosition), isFalse);
    game.world.spawn([SpecialPosition(2)]);
    game.pump();
    expect(game.world.query<Position>().count(), 2);
  });

  test('add creates the store of its static type only when exact', () {
    final game = TestGame.headless();
    final entity = game.world.spawn([]);
    game.start();
    game.world.add(entity, Brawler(4));
    expect(game.world.stores.isRegistered(Brawler), isTrue);
    final Object loose = Enemy();
    game.world.add(entity, loose);
    expect(game.world.stores.isRegistered(Object), isFalse);
    game.world.add(entity, Stunned());
    expect(game.world.stores.require(Stunned), isA<TagStore>());
    game.pump();
    expect(game.world.get<Brawler>(entity).power, 4);
    expect(game.world.has<Stunned>(entity), isTrue);
  });

  test('entitiesWith iterates tags with typed filters', () {
    final game = TestGame.headless();
    final plain = game.world.spawn([Enemy()]);
    game.world.spawn([Enemy(), Stunned()]);
    game.start();
    expect(game.world.entitiesWith<Enemy>().count(), 2);
    expect(
      game.world.entitiesWith<Enemy>().without<Stunned>().firstOrNull,
      plain,
    );
    expect(game.world.entitiesWith<Enemy>().having<Player>().isEmpty, isTrue);
  });

  test('store change listeners fan out and detach', () {
    final store = TestGame.headless().world.ensureObjectStore<Brawler>();
    final first = Recorder();
    final second = Recorder();
    store
      ..addChangeListener(first)
      ..addChangeListener(second)
      ..insert(1, Brawler(1))
      ..removeChangeListener(first)
      ..insert(2, Brawler(2))
      ..clear();
    expect(first.rows, [1]);
    expect(second.rows, [1, 2, -1]);
  });

  test('a conditional emit reaches the readers of each branch', () {
    final killed = <EnemyKilled>[];
    final cleared = <WaveCleared>[];
    final game = TestGame.headless(
      features: [
        (g) => g
          ..configureEvent<EnemyKilled>()
          ..configureEvent<WaveCleared>()
          ..addSystem(Schedules.update, (World world) {
            killed.addAll(world.events<EnemyKilled>());
            cleared.addAll(world.events<WaveCleared>());
          }),
      ],
    );
    game.start();
    for (final kill in [true, false]) {
      game.emit(kill ? EnemyKilled() : WaveCleared());
    }
    game.pump();
    expect(killed, hasLength(1));
    expect(cleared, hasLength(1));
  });
}
