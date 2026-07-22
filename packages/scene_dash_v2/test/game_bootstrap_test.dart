import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';

/// A resource whose [dispose] fires on `game.shutdown()` (reverse-order
/// teardown), so a test can observe that the game was actually shut down.
final class Teardown implements Disposable {
  bool disposed = false;
  @override
  void dispose() => disposed = true;
}

Future<WorldGame> boot({Teardown? teardown}) => WorldGame.boot(
  features: [if (teardown != null) (game) => game.world.insert(teardown)],
);

Widget host(Widget child) =>
    Directionality(textDirection: TextDirection.ltr, child: child);

void main() {
  testWidgets('holds the loading frame until boot completes, then builds '
      'the running game', (tester) async {
    final game = await boot();
    final gate = Completer<WorldGame>();

    await tester.pumpWidget(
      host(
        GameBootstrap<WorldGame>(
          boot: () => gate.future,
          loading: (_) => const Text('loading'),
          builder: (context, game) => Text('running ${identityHashCode(game)}'),
        ),
      ),
    );

    expect(find.text('loading'), findsOneWidget);
    expect(find.textContaining('running'), findsNothing);

    gate.complete(game);
    await tester.pumpAndSettle();

    expect(find.text('loading'), findsNothing);
    expect(find.text('running ${identityHashCode(game)}'), findsOneWidget);
  });

  testWidgets('shows the error frame when boot throws', (tester) async {
    await tester.pumpWidget(
      host(
        GameBootstrap<WorldGame>(
          boot: () async => throw StateError('shader bundle missing'),
          builder: (context, game) => const Text('running'),
          error: (context, error) => Text('failed: $error'),
        ),
      ),
    );
    await tester.pump(); // let the failed future settle

    expect(find.textContaining('shader bundle missing'), findsOneWidget);
    expect(find.text('running'), findsNothing);
  });

  testWidgets('boots once, not on every rebuild', (tester) async {
    final game = await boot();
    var boots = 0;
    Future<WorldGame> bootOnce() async {
      boots++;
      return game;
    }

    late StateSetter rebuild;
    await tester.pumpWidget(
      host(
        StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return GameBootstrap<WorldGame>(
              boot: bootOnce,
              builder: (context, game) => const Text('running'),
            );
          },
        ),
      ),
    );
    await tester.pump();

    rebuild(() {}); // a parent rebuild must not re-boot
    await tester.pump();

    expect(boots, 1);
    expect(find.text('running'), findsOneWidget);
  });

  testWidgets('shuts the game down when disposed', (tester) async {
    final teardown = Teardown();
    final game = await boot(teardown: teardown);

    await tester.pumpWidget(
      host(
        GameBootstrap<WorldGame>(
          boot: () async => game,
          builder: (context, game) => const Text('running'),
        ),
      ),
    );
    await tester.pump();
    expect(teardown.disposed, isFalse);

    await tester.pumpWidget(host(const Text('gone'))); // dispose the bootstrap
    await tester.pump();

    expect(teardown.disposed, isTrue);
  });

  testWidgets('a boot that finishes after dispose is shut down, not leaked', (
    tester,
  ) async {
    final teardown = Teardown();
    final game = await boot(teardown: teardown);
    final gate = Completer<WorldGame>();

    await tester.pumpWidget(
      host(
        GameBootstrap<WorldGame>(
          boot: () => gate.future,
          builder: (context, game) => const Text('running'),
        ),
      ),
    );

    // Gone before boot ever finishes.
    await tester.pumpWidget(host(const Text('gone')));
    expect(teardown.disposed, isFalse); // nothing to dispose yet

    // The late boot resolves onto a widget that no longer exists.
    gate.complete(game);
    await tester.pump();

    expect(teardown.disposed, isTrue);
  });
}
