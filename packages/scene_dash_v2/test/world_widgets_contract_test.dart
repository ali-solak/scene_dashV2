import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';

final class Inventory {
  final items = <String>['sword'];
}

final class Hit {
  const Hit(this.id);
  final int id;
}

Future<WorldGame> boot(WidgetTester tester) async {
  final game = await WorldGame.boot();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    await game.shutdown();
  });
  return game;
}

void tick(WorldGame game) =>
    game.onTick(const Duration(milliseconds: 16), 1 / 60);

Widget label(Object? value) => Text('$value', textDirection: TextDirection.ltr);

void main() {
  testWidgets('unmounting event widgets unregisters their readers', (
    tester,
  ) async {
    final game = await boot(tester);
    for (var i = 0; i < 10; i++) {
      await tester.pumpWidget(
        GameScope(
          game: game,
          child: WorldEventListener<Hit>(
            onEvent: (_, _) {},
            child: const SizedBox(),
          ),
        ),
      );
      expect(game.world.eventChannel<Hit>().readerCount, 1);
      await tester.pumpWidget(const SizedBox());
      expect(game.world.eventChannel<Hit>().readerCount, 0);
    }
  });

  for (final matching in [false, true]) {
    testWidgets('EntityBuilder ${matching ? 'matching' : 'handle'} compares '
        'copied lists and handles absence', (tester) async {
      final game = await boot(tester);
      final inventory = Inventory();
      final entity = game.world.spawn([inventory]);
      tick(game);
      var builds = 0;
      Widget builder(BuildContext context, List<String> items) {
        builds++;
        return label(items.join(','));
      }

      final child = matching
          ? EntityBuilder<Inventory, List<String>>.matching(
              select: (i) => List.of(i.items),
              equals: listEquals,
              builder: builder,
              absent: label('absent'),
            )
          : EntityBuilder<Inventory, List<String>>(
              entity: entity,
              select: (i) => List.of(i.items),
              equals: listEquals,
              builder: builder,
              absent: label('absent'),
            );
      await tester.pumpWidget(GameScope(game: game, child: child));
      tick(game);
      await tester.pump();
      expect(builds, 1, reason: 'equal copies do not trigger frame rebuilds');
      inventory.items.add('shield');
      tick(game);
      await tester.pump();
      expect(builds, 2);
      expect(find.text('sword,shield'), findsOneWidget);
      game.world.despawn(entity);
      tick(game);
      await tester.pump();
      expect(find.text('absent'), findsOneWidget);
      if (matching) {
        game.world.spawn([Inventory()..items.add('shield')]);
        tick(game);
        await tester.pump();
        expect(
          builds,
          3,
          reason: 'presence changes rebuild even for equal values',
        );
      }
    });
  }

  testWidgets(
    'EntityBuilder accepts nullable selections and updated equality',
    (tester) async {
      final game = await boot(tester);
      final inventory = Inventory();
      final entity = game.world.spawn([inventory]);
      tick(game);
      var builds = 0;
      var compares = 0;
      Widget tree(bool suppress) => GameScope(
        game: game,
        child: EntityBuilder<Inventory, String?>(
          entity: entity,
          select: (i) => i.items.firstOrNull,
          equals: (a, b) {
            compares++;
            return suppress || a == b;
          },
          builder: (_, item) {
            builds++;
            return label(item);
          },
        ),
      );
      await tester.pumpWidget(tree(true));
      inventory.items.clear();
      tick(game);
      await tester.pump();
      expect(builds, 1);
      expect(compares, 1);
      await tester.pumpWidget(tree(false));
      expect(
        find.text('null'),
        findsOneWidget,
        reason: 'widget updates refresh regardless of equality',
      );
      tick(game);
      await tester.pump();
      expect(builds, 2, reason: 'equal nulls suppress frame rebuilds');
      inventory.items.add('bow');
      tick(game);
      await tester.pump();
      expect(find.text('bow'), findsOneWidget);
      expect(builds, 3);
    },
  );

  testWidgets(
    'callback failures report errors without replay or skipped siblings',
    (tester) async {
      final game = await boot(tester);
      final attempts = <int>[];
      final sibling = <int>[];
      await tester.pumpWidget(
        GameScope(
          game: game,
          child: WorldEventListener<Hit>(
            onEvent: (_, hit) {
              attempts.add(hit.id);
              if (hit.id == 2) throw StateError('failed callback');
              if (hit.id == 1) game.emit(const Hit(4));
            },
            child: WorldEventListener<Hit>(
              onEvent: (_, hit) => sibling.add(hit.id),
              child: const SizedBox(),
            ),
          ),
        ),
      );
      for (final id in [1, 2, 3]) {
        game.emit(Hit(id));
      }
      tick(game);
      expect(tester.takeException(), isA<StateError>());
      expect(attempts, [
        1,
        2,
        3,
      ], reason: 'the rest of the batch must still run');
      tick(game);
      await tester.pump();
      expect(attempts, [
        1,
        2,
        3,
        4,
      ], reason: 'new events wait; old events never replay');
      expect(sibling, [
        1,
        2,
        3,
        4,
      ], reason: 'each listener has an independent reader');
      tick(game);
      expect(attempts, [1, 2, 3, 4]);
      expect(tester.takeException(), isNull);
    },
  );

  for (final mode in ['world', 'handle', 'matching']) {
    testWidgets('$mode rejects negative polling on mount and widget update', (
      tester,
    ) async {
      final game = await boot(tester);
      final entity = game.world.spawn([Inventory()]);
      tick(game);
      var selects = 0;
      int select(Inventory i) {
        selects++;
        return i.items.length;
      }

      Widget tree(Duration every) => GameScope(
        game: game,
        child: switch (mode) {
          'handle' => EntityBuilder<Inventory, int>(
            entity: entity,
            every: every,
            select: select,
            builder: (_, n) => label(n),
          ),
          'matching' => EntityBuilder<Inventory, int>.matching(
            every: every,
            select: select,
            builder: (_, n) => label(n),
          ),
          _ => WorldBuilder<int>(
            every: every,
            select: (w) => select(w.query<Inventory>().first.$2),
            builder: (_, n) => label(n),
          ),
        },
      );
      const invalid = Duration(microseconds: -1);
      await tester.pumpWidget(tree(invalid));
      expect(tester.takeException(), isArgumentError);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(tree(Duration.zero));
      final baseline = selects;
      tick(game);
      tick(game);
      await tester.pump();
      expect(
        selects,
        baseline + 2,
        reason: 'zero is valid and polls every frame',
      );
      await tester.pumpWidget(tree(invalid));
      expect(tester.takeException(), isArgumentError);
    });
  }

  test('pulse rejects zero, negative, infinite and NaN durations', () {
    for (final duration in [
      0.0,
      -1.0,
      double.infinity,
      double.negativeInfinity,
      double.nan,
    ]) {
      expect(
        () => WorldBuilder<int>.pulse(
          select: (_) => 1,
          trigger: (_, _) => true,
          duration: duration,
          pulseBuilder: (_, _, _) => const SizedBox(),
        ),
        throwsAssertionError,
        reason: 'duration: $duration',
      );
    }
  });
}
