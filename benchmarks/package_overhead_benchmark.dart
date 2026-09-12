import 'package:scene_dash_v2_core/scene_dash_v2_core.dart';
import 'package:scene_dash_v2_core/advanced.dart'
    show App, EventChannel, EventReader;
import 'package:scene_dash_v2_benchmarks/harness.dart';

class Unregistered {
  Unregistered(this.value);
  final int value;
}

class Position {
  double x = 0;
}

class Handle implements Disposable {
  bool disposed = false;
  @override
  void dispose() {
    disposed = true;
  }
}

Future<void> main() async {
  var sink = 0;
  for (final count in [0, 1000, 10000]) {
    final game = TestGame.headless(
      features: [(g) => g.registerComponent<Position>()],
    );
    for (var i = 0; i < count; i++) {
      game.world.spawn([Unregistered(i)]);
    }
    game.start();
    benchRepeat('empty Position query; $count parked parts', 1, () {
      sink += game.world.query<Position>().count();
    });
    // This typed read claims the parked components; subsequent Position
    // reads then avoid scanning unrelated unregistered parts.
    game.world.query<Unregistered>().count();
    if (count == 10000) {
      benchRepeat('same world after claiming parked parts', 1, () {
        sink += game.world.query<Position>().count();
      });
    }
    await game.shutdown();
  }
  for (final count in [0, 1000, 10000]) {
    EventReader<int> setup() {
      final channel = EventChannel<int>();
      final reader = channel.reader();
      for (var i = 0; i < count; i++) {
        channel.send(i);
      }
      return reader;
    }

    // Isolate the cursor operation behind world.consumeAny(), excluding
    // channel construction, event emission, and system dispatch.
    benchSetup(
      'drain().isNotEmpty; $count events',
      1,
      setup: setup,
      run: (reader) {
        if (reader.drain().isNotEmpty) sink++;
      },
    );
    benchSetup(
      'consume(); $count events',
      1,
      setup: setup,
      run: (reader) {
        if (reader.consume()) sink++;
      },
    );
  }
  final app = App();
  final handle = Handle();
  app.insertResource(handle);
  var cleanupRan = false;
  app.addCleanup(() {
    cleanupRan = true;
  });
  app.addCleanup(() {
    throw StateError('cleanup failure');
  });
  app.start();
  try {
    await app.shutdown();
  } catch (_) {}
  await app.shutdown();
  print(
    'After throwing cleanup + retry: earlier cleanup=$cleanupRan, resource disposed=${handle.disposed}',
  );
  print('sink=$sink');
}
