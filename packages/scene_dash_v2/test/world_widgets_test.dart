import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';

enum RunMode { title, playing }

final class Health {
  Health(this.max) : current = max;
  double current;
  final double max;
}

final class HitLanded {
  final int damage;
  const HitLanded(this.damage);
}

Future<WorldGame> boot({List<Feature> features = const <Feature>[]}) =>
    WorldGame.boot(features: features);

void drive(WorldGame game, [int frames = 1]) {
  for (var i = 0; i < frames; i++) {
    game.onTick(Duration(milliseconds: 16 * (i + 1)), 1 / 60);
  }
}

void main() {
  testWidgets('GameScope provides the game; context extensions read it; '
      'of() outside throws', (tester) async {
    final game = await boot();
    WorldGame? seen;
    late BuildContext outside;
    await tester.pumpWidget(
      Builder(builder: (context) {
        outside = context;
        return GameScope(
          game: game,
          child: Builder(builder: (context) {
            seen = context.game;
            return const SizedBox();
          }),
        );
      }),
    );
    expect(seen, same(game));
    expect(GameScope.maybeOf(outside), isNull);
    expect(() => GameScope.of(outside), throwsFlutterError);
  });

  testWidgets('GameHost installs the scope and survives reassemble',
      (tester) async {
    final game = await boot();
    await tester.pumpWidget(GameHost(game: game, child: const SizedBox()));
    // reassembleApplication completes at end-of-frame, which the test
    // binding only reaches on pump — awaiting it bare would deadlock.
    final reassembled = tester.binding.reassembleApplication();
    await tester.pump();
    await reassembled;
    expect(find.byType(SizedBox), findsOneWidget);
  });

  testWidgets('EntityBuilder rebuilds only when the selected value '
      'changes, and falls back while the component is gone', (tester) async {
    final game = await boot();
    final health = Health(100);
    final entity = game.world.spawn([health]);
    drive(game);
    var builds = 0;
    await tester.pumpWidget(
      GameScope(
        game: game,
        child: EntityBuilder<Health, double>(
          entity: entity,
          select: (h) => h.current,
          builder: (context, hp) {
            builds++;
            return Text('$hp', textDirection: TextDirection.ltr);
          },
          absent: const Text('dead', textDirection: TextDirection.ltr),
        ),
      ),
    );
    expect(find.text('100.0'), findsOneWidget);
    expect(builds, 1);
    drive(game, 2);
    await tester.pump();
    expect(builds, 1, reason: 'unchanged value: no rebuild');
    health.current = 60;
    drive(game);
    await tester.pump();
    expect(find.text('60.0'), findsOneWidget);
    expect(builds, 2);
    game.world.despawn(entity);
    drive(game);
    await tester.pump();
    expect(find.text('dead'), findsOneWidget);
  });

  testWidgets('WorldBuilder watches world-derived values (query counts)',
      (tester) async {
    final game = await boot();
    game.world.spawn([Health(1)]);
    drive(game);
    await tester.pumpWidget(
      GameScope(
        game: game,
        child: WorldBuilder<int>(
          select: (world) => world.query<Health>().count(),
          builder: (context, count) =>
              Text('$count', textDirection: TextDirection.ltr),
        ),
      ),
    );
    expect(find.text('1'), findsOneWidget);
    game.world.spawn([Health(2)]);
    drive(game);
    await tester.pump();
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('GameStateBuilder routes on transitions', (tester) async {
    final game = await boot(features: [
      (game) => game.addState(RunMode.title),
    ]);
    drive(game);
    await tester.pumpWidget(
      GameScope(
        game: game,
        child: GameStateBuilder<RunMode>(
          builder: (context, s) =>
              Text(s.name, textDirection: TextDirection.ltr),
        ),
      ),
    );
    expect(find.text('title'), findsOneWidget);
    game.world.setState(RunMode.playing);
    drive(game);
    await tester.pump();
    expect(find.text('playing'), findsOneWidget);
  });

  testWidgets('WorldEventListener delivers once per frame and cleans up '
      'with the widget', (tester) async {
    final game = await boot();
    drive(game);
    final seen = <int>[];
    await tester.pumpWidget(
      GameScope(
        game: game,
        child: WorldEventListener<HitLanded>(
          onEvent: (context, hit) => seen.add(hit.damage),
          child: const SizedBox(),
        ),
      ),
    );
    game.world
      ..emit(const HitLanded(5))
      ..emit(const HitLanded(7));
    drive(game);
    await tester.pump();
    expect(seen, [5, 7]);

    await tester.pumpWidget(GameScope(game: game, child: const SizedBox()));
    game.world.emit(const HitLanded(9));
    drive(game, 3);
    expect(seen, [5, 7], reason: 'released reader: no delivery, no lag');
  });

  testWidgets('WorldInspector lists named entities', (tester) async {
    final game = await boot();
    game.world.spawn([const Name('Boss'), Health(500)]);
    drive(game);
    await tester.pumpWidget(
      GameScope(game: game, child: const WorldInspector()),
    );
    expect(find.textContaining('"Boss"'), findsOneWidget);
  });
}
