import 'package:scene_dash_v2_core/advanced.dart' show SnapshotCollector;
import 'package:scene_dash_v2_core/scene_dash_v2_core.dart';
import 'package:test/test.dart';

final class _Health {
  _Health(this.current, this.max);
  final int current;
  final int max;

  @override
  String toString() => 'hp $current/$max';
}

/// Counts `toString` calls so tests can prove summaries never render
/// component values — detail stays lazy (I2).
final class _Tattling {
  static int toStringCalls = 0;

  @override
  String toString() {
    toStringCalls++;
    return 'tattled';
  }
}

final class _Pos {
  double x = 0;
}

final class _NamedResource {
  @override
  String toString() => 'named-resource';
}

final class _PlainResource {}

final class _Ping {}

void moverSystem(World world) {
  world.query<_Pos>().each((entity, pos) => pos.x += 1);
}

/// Registers the test component stores up front, so untyped spawns flush
/// at the frame boundary instead of parking until a typed use site.
void _registerTypes(GameBuilder game) {
  game
    ..registerComponent<Name>()
    ..registerComponent<_Health>()
    ..registerComponent<_Tattling>()
    ..registerComponent<_Pos>();
}

void main() {
  group('SnapshotCollector.collect', () {
    test('world counts, per-store counts, entity summaries with names and '
        'type names', () {
      final game = TestGame.headless(features: [_registerTypes]);
      final boss = game.world.spawn([const Name('Boss'), _Health(75, 100)]);
      game.world.spawn([_Pos()]);
      game.world.spawn([_Pos()]);
      game.pump(); // flush the deferred spawns

      final snapshot = SnapshotCollector(game.world).collect();

      expect(snapshot.entityCount, 3);
      final healthStore = snapshot.stores.singleWhere(
        (store) => store.type == '_Health',
      );
      expect(healthStore.count, 1);
      final posStore = snapshot.stores.singleWhere(
        (store) => store.type == '_Pos',
      );
      expect(posStore.count, 2);

      final bossSummary = snapshot.entities.singleWhere(
        (entity) => entity.name == 'Boss',
      );
      expect(bossSummary.index, boss.index);
      expect(bossSummary.generation, boss.generation);
      expect(bossSummary.componentTypes, contains('_Health'));
      final unnamed = snapshot.entities.where((e) => e.name == null);
      expect(unnamed, hasLength(2));
    });

    test('summaries carry component type names only — values are never '
        'rendered during collect (detail-laziness)', () {
      final game = TestGame.headless(features: [_registerTypes]);
      final entity = game.world.spawn([_Tattling()]);
      game.pump(); // flush the deferred spawn
      _Tattling.toStringCalls = 0;

      final collector = SnapshotCollector(game.world);
      final snapshot = collector.collect();
      expect(
        _Tattling.toStringCalls,
        0,
        reason: 'collect must not touch component toString',
      );
      expect(snapshot.entities.single.componentTypes, contains('_Tattling'));

      final detail = collector.describeEntity(entity.index, entity.generation);
      expect(
        _Tattling.toStringCalls,
        1,
        reason: 'detail renders values, on selection only',
      );
      expect(detail.lines, contains('tattled'));
    });

    test('resources: type names, toString only where overridden', () {
      final game = TestGame.headless();
      game.world.resources
        ..insert(_NamedResource())
        ..insert(_PlainResource());

      final snapshot = SnapshotCollector(game.world).collect();

      final named = snapshot.resources.singleWhere(
        (resource) => resource.type == '_NamedResource',
      );
      expect(named.value, 'named-resource');
      final plain = snapshot.resources.singleWhere(
        (resource) => resource.type == '_PlainResource',
      );
      expect(
        plain.value,
        isNull,
        reason: 'default Instance-of toString is filtered, as in M6',
      );
    });

    test('systems: label, schedule, last and average ms from the profiler', () {
      final game = TestGame.headless(
        diagnostics: const AppDiagnostics(profileSystems: true),
        features: [(game) => game.addSystem(Schedules.update, moverSystem)],
      );
      game.world.spawn([_Pos()]);
      game.pump();
      game.pump();

      final snapshot = SnapshotCollector(game.world).collect();

      // The D11 label carries the registration disambiguator (`@0`).
      final mover = snapshot.systems.where(
        (s) => s.label.startsWith('moverSystem'),
      );
      expect(mover, isNotEmpty, reason: 'profiled system appears by label');
      final timing = mover.first;
      expect(timing.schedule, isNotEmpty);
      expect(timing.lastMs, greaterThanOrEqualTo(0));
      expect(timing.averageMs, greaterThanOrEqualTo(0));
    });

    test('systems list is empty without profiling enabled', () {
      final game = TestGame.headless(
        features: [(game) => game.addSystem(Schedules.update, moverSystem)],
      );
      game.pump();
      expect(SnapshotCollector(game.world).collect().systems, isEmpty);
    });

    test('events: channel type name, pending count, lagging flag', () {
      final game = TestGame.headless();
      game.world.registerEvent<_Ping>();
      game.world
        ..sendEvent(_Ping())
        ..sendEvent(_Ping());

      final snapshot = SnapshotCollector(game.world).collect();

      final channel = snapshot.events.singleWhere(
        (event) => event.type == '_Ping',
      );
      expect(channel.pending, 2);
      expect(channel.readerLagged, isFalse);
    });
  });

  group('SnapshotCollector.describeEntity', () {
    test('renders one M6 line per component: overridden toString value, '
        'type name otherwise', () {
      final game = TestGame.headless(features: [_registerTypes]);
      final boss = game.world.spawn([
        const Name('Boss'),
        _Health(75, 100),
        _Pos(),
      ]);
      game.pump(); // flush the deferred spawn

      final detail = SnapshotCollector(
        game.world,
      ).describeEntity(boss.index, boss.generation);

      expect(detail.stale, isFalse);
      expect(detail.name, 'Boss');
      expect(detail.lines, contains('hp 75/100'));
      expect(
        detail.lines,
        contains('_Pos'),
        reason: 'no toString override falls back to the type name',
      );
    });

    test('a stale handle reports stale with no lines', () {
      final game = TestGame.headless(features: [_registerTypes]);
      final entity = game.world.spawn([_Pos()]);
      game.pump(); // flush the deferred spawn
      game.world.despawnNow(entity);

      final detail = SnapshotCollector(
        game.world,
      ).describeEntity(entity.index, entity.generation);

      expect(detail.stale, isTrue);
      expect(detail.lines, isEmpty);
    });
  });
}
