import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scene_dash_inspector/scene_dash_inspector.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';
import 'package:scene_dash_v2_core/advanced.dart'
    show
        EntityDetailSnapshot,
        EntitySnapshot,
        EventChannelSnapshot,
        InspectorSnapshot,
        ResourceSnapshot,
        StoreSnapshot,
        SystemSnapshot;

const _fixed = InspectorSnapshot(
  entityCount: 2,
  stores: [
    StoreSnapshot(type: 'Health', count: 2),
    StoreSnapshot(type: 'Pos', count: 1),
  ],
  entities: [
    EntitySnapshot(
      index: 0,
      generation: 0,
      name: 'Boss',
      componentTypes: ['Health', 'Pos'],
    ),
    EntitySnapshot(
      index: 1,
      generation: 0,
      name: 'Grunt',
      componentTypes: ['Health'],
    ),
  ],
  resources: [
    ResourceSnapshot(type: 'Score', value: 'score 42'),
    ResourceSnapshot(type: 'PlainThing', value: null),
  ],
  systems: [
    SystemSnapshot(
        label: 'cheapSystem', schedule: 'update', lastMs: 0.1,
        averageMs: 0.1),
    SystemSnapshot(
        label: 'slowSystem', schedule: 'update', lastMs: 4.5,
        averageMs: 3.2),
  ],
  events: [
    EventChannelSnapshot(type: 'HitLanded', pending: 3, readerLagged: true),
  ],
);

Widget _panel({
  InspectorSnapshot snapshot = _fixed,
  EntityDetailSnapshot Function(int, int)? describe,
}) {
  return MaterialApp(
    home: Scaffold(
      body: InspectorPanel(
        snapshot: snapshot,
        describe: describe ??
            (index, generation) => EntityDetailSnapshot(
                  index: index,
                  generation: generation,
                  name: 'Boss',
                  lines: const ['hp 75/100', 'Pos'],
                  stale: false,
                ),
      ),
    ),
  );
}

void main() {
  testWidgets('renders every tab from a fixed snapshot', (tester) async {
    await tester.pumpWidget(_panel());

    // Entities tab (default).
    expect(find.text('2 entities'), findsOneWidget);
    expect(find.text('Entity(0 v0) "Boss"'), findsOneWidget);
    expect(find.text('Health, Pos'), findsOneWidget);

    await tester.tap(find.text('resources'));
    await tester.pump();
    expect(find.text('Score'), findsOneWidget);
    expect(find.text('score 42'), findsOneWidget);

    await tester.tap(find.text('systems'));
    await tester.pump();
    expect(find.text('slowSystem'), findsOneWidget);
    expect(find.text('4.50 ms (avg 3.20)'), findsOneWidget);

    await tester.tap(find.text('events'));
    await tester.pump();
    expect(find.text('HitLanded'), findsOneWidget);
    expect(find.text('pending 3'), findsOneWidget);
    expect(find.text('reader lagging'), findsOneWidget);
  });

  testWidgets('filters entities by Name substring', (tester) async {
    await tester.pumpWidget(_panel());

    await tester.enterText(
        find.byKey(const Key('inspector-filter')), 'bo');
    await tester.pump();

    expect(find.text('Entity(0 v0) "Boss"'), findsOneWidget);
    expect(find.text('Entity(1 v0) "Grunt"'), findsNothing);
  });

  testWidgets('requests detail only on tap, and back returns to the list',
      (tester) async {
    var describeCalls = 0;
    await tester.pumpWidget(_panel(describe: (index, generation) {
      describeCalls++;
      return EntityDetailSnapshot(
        index: index,
        generation: generation,
        name: 'Boss',
        lines: const ['hp 75/100'],
        stale: false,
      );
    }));

    expect(describeCalls, 0, reason: 'summary rendering must stay lazy');

    await tester.tap(find.byKey(const Key('inspector-entity-0')));
    await tester.pump();
    expect(describeCalls, 1);
    expect(find.text('hp 75/100'), findsOneWidget);

    await tester.tap(find.byKey(const Key('inspector-detail-back')));
    await tester.pump();
    expect(find.text('hp 75/100'), findsNothing);
    expect(describeCalls, 1, reason: 'closing detail asks for nothing');
  });

  testWidgets('sort-by-ms toggle reorders the systems list',
      (tester) async {
    await tester.pumpWidget(_panel());
    await tester.tap(find.text('systems'));
    await tester.pump();

    double y(String label) => tester.getTopLeft(find.text(label)).dy;
    expect(y('cheapSystem'), lessThan(y('slowSystem')),
        reason: 'registration order by default');

    await tester.tap(find.byKey(const Key('inspector-sort-ms')));
    await tester.pump();
    expect(y('slowSystem'), lessThan(y('cheapSystem')));
  });

  testWidgets('overlay: hidden renders nothing and never polls; visible '
      'polls on the configured cadence', (tester) async {
    final game = await WorldGame.boot(
      features: [(game) => game.registerComponent<_Marker>()],
    );
    game.world.spawn([_Marker()]);
    game.onTick(const Duration(milliseconds: 16), 1 / 60);

    Widget host({required bool visible}) => MaterialApp(
          home: GameScope(
            game: game,
            child: Stack(
              children: [
                InspectorOverlay(
                  visible: visible,
                  pollInterval: const Duration(milliseconds: 100),
                ),
              ],
            ),
          ),
        );

    await tester.pumpWidget(host(visible: false));
    expect(find.text('Inspector'), findsNothing);
    // No timer pending while hidden — pumping far ahead changes nothing.
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Inspector'), findsNothing);

    await tester.pumpWidget(host(visible: true));
    expect(find.text('Inspector'), findsOneWidget);
    expect(find.text('1 entities'), findsOneWidget);

    // A second spawn appears only after the next poll tick.
    game.world.spawn([_Marker()]);
    game.onTick(const Duration(milliseconds: 32), 1 / 60);
    await tester.pump(const Duration(milliseconds: 40));
    expect(find.text('1 entities'), findsOneWidget,
        reason: 'no fresh collect before the poll interval elapses');
    await tester.pump(const Duration(milliseconds: 70));
    expect(find.text('2 entities'), findsOneWidget);

    // Tear down so the periodic timer is cancelled before the test ends.
    await tester.pumpWidget(const SizedBox());
  });
}

final class _Marker {}
