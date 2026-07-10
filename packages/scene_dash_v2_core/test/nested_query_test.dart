import 'package:scene_dash_v2_core/scene_dash_v2_core.dart';
import 'package:test/test.dart';

/// The nested-query diagnostic (I5): a query iteration beginning while
/// another is active in the same system is the accidental O(N×M) shape,
/// reported once per system through the diagnostics sink. Product-mode
/// silence is by construction — the tracking runs entirely inside
/// `assert(() {...}())`, so release builds compile it out.
final class _PA {}

final class _PB {}

final class _Enemy {}

void nestedSystem(World world) {
  world.query2<_PA, _PB>().each((entity, a, b) {
    world.query<_Enemy>().each((inner, enemy) {});
  });
}

void sequentialSystem(World world) {
  world.query<_PA>().each((entity, a) {});
  world.query<_Enemy>().each((entity, enemy) {});
}

List<String> _nested(List<String> messages) =>
    messages.where((m) => m.startsWith('Nested query')).toList();

void main() {
  test('fires once per system, with the query labels and the row-count '
      'product', () {
    final messages = <String>[];
    final game = TestGame.headless(
      onDiagnostic: messages.add,
      features: [
        (game) => game
          // Registered up front so the parked spawns flush at the frame
          // boundary — not lazily inside the nested iteration under test.
          ..registerComponent<_PA>()
          ..registerComponent<_PB>()
          ..registerComponent<_Enemy>()
          ..addSystem(Schedules.update, nestedSystem),
      ],
    );
    game.world
      ..spawn([_PA(), _PB()])
      ..spawn([_PA(), _PB()])
      ..spawn([_Enemy()])
      ..spawn([_Enemy()])
      ..spawn([_Enemy()]);

    game.pump();
    game.pump();
    game.pump();

    final nested = _nested(messages);
    expect(nested, hasLength(1),
        reason: 'reported once per system, not once per frame or per row');
    expect(
      nested.single,
      'Nested query in nestedSystem: query<_Enemy> iterated inside '
      'query2<_PA, _PB>.each — ~2×3 comparisons per run. Hoist the inner '
      'query or restructure (see README query rules).',
    );
  });

  test('silent for sequential queries in one system', () {
    final messages = <String>[];
    final game = TestGame.headless(
      onDiagnostic: messages.add,
      features: [
        (game) => game.addSystem(Schedules.update, sequentialSystem),
      ],
    );
    game.world
      ..spawn([_PA()])
      ..spawn([_Enemy()]);

    game.pump();
    game.pump();

    expect(_nested(messages), isEmpty);
  });
}
