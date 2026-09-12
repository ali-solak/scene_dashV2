import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';

class Health {
  Health(this.current, {this.max = 100});
  double current;
  final double max;
}

final class Marked implements Tag {
  const Marked();
}

final class Hit {
  const Hit(this.damage);
  final int damage;
}

Future<WorldGame> boot(
  WidgetTester tester, {
  List<Feature> features = const [],
}) async {
  final game = await WorldGame.boot(features: features);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    await game.shutdown();
  });
  return game;
}

void tick(WorldGame game, [double delta = 1 / 60]) =>
    game.onTick(Duration(microseconds: (delta * 1e6).round()), delta);

Widget label(Object? value) => Text('$value', textDirection: TextDirection.ltr);

void main() {
  testWidgets('entity replacement refreshes during a polling interval', (
    tester,
  ) async {
    final game = await boot(tester);
    final first = game.world.spawn([Health(100)]);
    final second = game.world.spawn([Health(40)]);
    final absent = game.world.spawn([]);
    tick(game);
    Widget tree(Entity entity) => GameScope(
      game: game,
      child: EntityBuilder<Health, double>(
        entity: entity,
        every: const Duration(seconds: 1),
        select: (h) => h.current,
        builder: (_, value) => label(value),
        absent: label('absent'),
      ),
    );
    await tester.pumpWidget(tree(first));
    tick(game);
    await tester.pump();
    await tester.pumpWidget(tree(second));
    expect(find.text('40.0'), findsOneWidget);
    await tester.pumpWidget(tree(absent));
    expect(find.text('absent'), findsOneWidget);
    await tester.pumpWidget(tree(first));
    expect(find.text('100.0'), findsOneWidget);
  });

  testWidgets('entity selector refreshes with updated captured configuration', (
    tester,
  ) async {
    final game = await boot(tester);
    final entity = game.world.spawn([Health(40)]);
    tick(game);
    var showMax = false;
    double select(Health health) => showMax ? health.max : health.current;
    Widget tree() => GameScope(
      game: game,
      child: EntityBuilder<Health, double>(
        entity: entity,
        select: select,
        builder: (_, value) => label(value),
      ),
    );
    await tester.pumpWidget(tree());
    expect(find.text('40.0'), findsOneWidget);
    showMax = true;
    await tester.pumpWidget(tree());
    expect(find.text('100.0'), findsOneWidget);
  });

  testWidgets('entity filters and handle/matching modes refresh immediately', (
    tester,
  ) async {
    final game = await boot(tester, features: [(g) => g.registerTag<Marked>()]);
    game.world.spawn([Health(100)]);
    final marked = game.world.spawn([Health(40), const Marked()]);
    tick(game);
    Widget matching({
      List<Type> require = const [],
      List<Type> exclude = const [],
    }) => GameScope(
      game: game,
      child: EntityBuilder<Health, double>.matching(
        require: require,
        exclude: exclude,
        select: (h) => h.current,
        builder: (_, value) => label(value),
      ),
    );
    await tester.pumpWidget(matching());
    expect(find.text('100.0'), findsOneWidget);
    await tester.pumpWidget(matching(require: [Marked]));
    expect(find.text('40.0'), findsOneWidget);
    await tester.pumpWidget(matching(exclude: [Marked]));
    expect(find.text('100.0'), findsOneWidget);
    await tester.pumpWidget(
      GameScope(
        game: game,
        child: EntityBuilder<Health, double>(
          entity: marked,
          select: (h) => h.current,
          builder: (_, value) => label(value),
        ),
      ),
    );
    expect(find.text('40.0'), findsOneWidget);
    await tester.pumpWidget(matching(exclude: [Marked]));
    expect(find.text('100.0'), findsOneWidget);
  });

  testWidgets(
    'world selector replacement refreshes during a polling interval',
    (tester) async {
      final game = await boot(tester);
      Widget tree(int? value) => GameScope(
        game: game,
        child: WorldBuilder<int?>(
          every: const Duration(seconds: 1),
          select: (_) => value,
          builder: (_, selected) => label(selected),
        ),
      );
      await tester.pumpWidget(tree(1));
      tick(game);
      await tester.pump();
      await tester.pumpWidget(tree(2));
      expect(find.text('2'), findsOneWidget);
      await tester.pumpWidget(tree(null));
      expect(find.text('null'), findsOneWidget);
    },
  );

  testWidgets('simultaneous game and selector changes read the new world', (
    tester,
  ) async {
    final first = await boot(tester);
    final second = await boot(
      tester,
      features: [(g) => g.registerTag<Marked>()],
    );
    first.world.spawn([Health(100)]);
    second.world.spawn([Health(40), const Marked()]);
    tick(first);
    tick(second);
    Widget tree(WorldGame game, List<Type> require) => GameScope(
      game: game,
      child: Column(
        children: [
          EntityBuilder<Health, double>.matching(
            require: require,
            select: (h) => h.current,
            builder: (_, value) => label(value),
          ),
          WorldBuilder<int>(
            select: (w) => w.query<Health>(require: require).count(),
            builder: (_, count) => label('count: $count'),
          ),
        ],
      ),
    );
    await tester.pumpWidget(tree(first, []));
    // Marked is deliberately unregistered in the old world: reading it
    // before didChangeDependencies attaches the new game would throw.
    await tester.pumpWidget(tree(second, [Marked]));
    expect(tester.takeException(), isNull);
    expect(find.text('40.0'), findsOneWidget);
    expect(find.text('count: 1'), findsOneWidget);
  });

  testWidgets('active pulse resets on game replacement and detaches old game', (
    tester,
  ) async {
    final first = await boot(tester);
    final second = await boot(tester);
    final firstHealth = Health(100);
    final secondHealth = Health(80);
    first.world.spawn([firstHealth]);
    second.world.spawn([secondHealth]);
    tick(first);
    tick(second);
    final child = WorldBuilder<double>.pulse(
      select: (w) => w.query<Health>().first.$2.current,
      trigger: (previous, next) => next < previous,
      duration: 1,
      pulseBuilder: (_, pulse, _) => label(pulse),
    );
    await tester.pumpWidget(GameScope(game: first, child: child));
    firstHealth.current = 50;
    tick(first);
    await tester.pump();
    expect(find.text('1.0'), findsOneWidget);
    await tester.pumpWidget(GameScope(game: second, child: child));
    expect(find.text('0.0'), findsOneWidget);
    secondHealth.current = 20;
    tick(first);
    await tester.pump();
    expect(find.text('0.0'), findsOneWidget, reason: 'old game is detached');
    tick(second);
    await tester.pump();
    expect(find.text('1.0'), findsOneWidget);
  });

  testWidgets('switching plain/pulse modes establishes a fresh baseline', (
    tester,
  ) async {
    final game = await boot(tester);
    var value = 100;
    Widget tree(bool pulse) => GameScope(
      game: game,
      child: pulse
          ? WorldBuilder<int>.pulse(
              select: (_) => value,
              trigger: (previous, next) => next < previous,
              duration: 1,
              pulseBuilder: (_, pulse, _) => label(pulse),
            )
          : WorldBuilder<int>(
              select: (_) => value,
              builder: (_, value) => label(value),
            ),
    );
    await tester.pumpWidget(tree(false));
    value = 50;
    await tester.pumpWidget(tree(true));
    tick(game);
    await tester.pump();
    expect(find.text('0.0'), findsOneWidget);
    value = 40;
    tick(game);
    await tester.pump();
    expect(find.text('1.0'), findsOneWidget);
    value = 30;
    await tester.pumpWidget(tree(false));
    expect(find.text('30'), findsOneWidget);
    await tester.pumpWidget(tree(true));
    tick(game);
    await tester.pump();
    expect(find.text('0.0'), findsOneWidget, reason: 'old pulse cannot return');
  });

  testWidgets(
    'parent rebuilds preserve pulse decay with new inline callbacks',
    (tester) async {
      final game = await boot(tester);
      var value = 100;
      double seen = -1;
      Widget tree() => GameScope(
        game: game,
        child: WorldBuilder<int>.pulse(
          select: (_) => value,
          trigger: (previous, next) => next < previous,
          duration: 1,
          pulseBuilder: (_, pulse, _) {
            seen = pulse;
            return label(pulse);
          },
        ),
      );
      await tester.pumpWidget(tree());
      // A changed selection on widget update is a baseline, not an event.
      value = 80;
      await tester.pumpWidget(tree());
      tick(game);
      await tester.pump();
      expect(seen, 0);
      value = 50;
      tick(game);
      await tester.pump();
      expect(seen, 1);
      tick(game, 0.25);
      await tester.pump();
      expect(seen, 0.75);
      await tester.pumpWidget(tree());
      expect(seen, 0.75);
      tick(game, 0.25);
      await tester.pump();
      expect(seen, 0.5);
    },
  );

  for (final entityBuilder in [false, true]) {
    testWidgets(
      '${entityBuilder ? 'entity' : 'world'} polling resets on interval '
      'and game changes, but keeps its phase on parent rebuilds',
      (tester) async {
        final first = await boot(tester);
        final second = await boot(tester);
        first.world.spawn([Health(100)]);
        second.world.spawn([Health(40)]);
        tick(first);
        tick(second);
        var selects = 0;
        Widget tree(WorldGame game, Duration? every) => GameScope(
          game: game,
          child: entityBuilder
              ? EntityBuilder<Health, double>.matching(
                  every: every,
                  select: (h) {
                    selects++;
                    return h.current;
                  },
                  builder: (_, value) => label(value),
                )
              : WorldBuilder<double>(
                  every: every,
                  select: (w) {
                    selects++;
                    return w.query<Health>().first.$2.current;
                  },
                  builder: (_, value) => label(value),
                ),
        );
        const interval = Duration(seconds: 1);
        await tester.pumpWidget(tree(first, interval));
        tick(first);
        await tester.pump();
        await tester.pumpWidget(tree(first, interval));
        var baseline = selects;
        tick(first);
        await tester.pump();
        expect(selects, baseline, reason: 'same interval keeps its phase');
        await tester.pumpWidget(tree(first, const Duration(seconds: 2)));
        baseline = selects;
        tick(first);
        await tester.pump();
        expect(
          selects,
          baseline + 1,
          reason: 'new interval polls on first tick',
        );
        await tester.pumpWidget(tree(second, const Duration(seconds: 2)));
        expect(find.text('40.0'), findsOneWidget);
        baseline = selects;
        tick(first);
        await tester.pump();
        expect(selects, baseline, reason: 'old game must be detached');
        tick(second);
        await tester.pump();
        expect(selects, baseline + 1, reason: 'new game polls on first tick');
        await tester.pumpWidget(tree(second, null));
        baseline = selects;
        tick(second);
        tick(second);
        await tester.pump();
        expect(
          selects,
          baseline + 2,
          reason: 'null restores every-frame polling',
        );
        await tester.pumpWidget(tree(second, interval));
        baseline = selects;
        tick(second);
        await tester.pump();
        expect(selects, baseline + 1);
        tick(second);
        await tester.pump();
        expect(selects, baseline + 1, reason: 'throttling resumes');
      },
    );
  }

  testWidgets('event listener switches games and releases its final reader', (
    tester,
  ) async {
    final first = await boot(tester);
    final second = await boot(tester);
    final seen = <int>[];
    final child = WorldEventListener<Hit>(
      onEvent: (_, hit) => seen.add(hit.damage),
      child: const SizedBox(),
    );
    await tester.pumpWidget(GameScope(game: first, child: child));
    first.emit(const Hit(1));
    tick(first);
    await tester.pump();
    await tester.pumpWidget(GameScope(game: second, child: child));
    first.emit(const Hit(2));
    second.emit(const Hit(3));
    tick(first);
    tick(second);
    await tester.pump();
    expect(seen, [1, 3]);
    await tester.pumpWidget(const SizedBox());
    second.emit(const Hit(4));
    tick(second);
    expect(seen, [1, 3]);
    expect(tester.takeException(), isNull);
  });
}
