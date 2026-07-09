// Headless dispatch-at-scale benchmark: what the frame *skeleton* costs once a
// game grows to hundreds of systems and thousands of query executions per
// frame — dispatch, run-condition gating, per-query fixed overhead, and event
// channel maintenance. Per-entity iteration cost is covered by the other
// benchmarks; this one isolates the fixed costs that scale with system and
// query count.
//
// Run: dart run schedule_dispatch_benchmark.dart [systemCount]
import 'package:scene_dash_v2_core/advanced.dart';
import 'package:scene_dash_v2_benchmarks/harness.dart';

final class Stat {
  double value = 0;
}

final class Flag {
  const Flag();
}

/// The floor: a system that does nothing, so runs measure pure dispatch.
final class _NoopAdapter implements SystemAdapter {
  @override
  void initialize(World world) {}

  @override
  void run() {}
}

/// A realistic small system: one selective query (16 matches out of the whole
/// world) mutating a field per match.
final class _TinyQueryAdapter implements SystemAdapter {
  late final Query1<Stat> _query;

  @override
  void initialize(World world) {
    world.ensureObjectStore<Stat>();
    world.ensureTagStore<Flag>();
    _query = world.query1<Stat>(withTypes: const <Type>[Flag]);
  }

  @override
  void run() {
    _query.each((entity, stat) => stat.value += 1);
  }
}

/// Spawns [total] entities with [flagged] of them carrying the Flag tag, so
/// the tiny query drives from a 16-entity store inside a big world.
void _populate(World world, {required int total, required int flagged}) {
  world
    ..ensureObjectStore<Stat>()
    ..ensureTagStore<Flag>();
  for (var i = 0; i < total; i++) {
    final entity = world.entities.spawn();
    world.insertNow<Stat>(entity, Stat());
    if (i < flagged) world.insertNow<Flag>(entity, const Flag());
  }
}

App _appWithSystems(
  int count,
  SystemAdapter Function() adapter, {
  bool gateHalf = false,
}) {
  final app = App(accessConflictPolicy: AccessConflictPolicy.ignore);
  _populate(app.world, total: 10000, flagged: 16);
  for (var i = 0; i < count; i++) {
    final gated = gateHalf && (i & 1) == 1;
    app.addSystemAdapter(
      adapter(),
      schedule: Schedules.update,
      label: SystemLabel('bench.system$i'),
      runIf: gated ? (world) => false : null,
    );
  }
  app.start();
  return app;
}

void main(List<String> args) {
  final systems = entityCount(args, fallback: 400);

  section('Frame skeleton at scale', entities: systems);

  final noop = _appWithSystems(systems, _NoopAdapter.new);
  benchRepeat('dispatch: $systems no-op systems', systems, () {
    noop.runSchedule(Schedules.update);
  });

  final gated = _appWithSystems(systems, _NoopAdapter.new, gateHalf: true);
  benchRepeat('dispatch: half gated off by runIf', systems, () {
    gated.runSchedule(Schedules.update);
  });

  final querying = _appWithSystems(systems, _TinyQueryAdapter.new);
  benchRepeat('$systems systems, each a 16-match query', systems, () {
    querying.runSchedule(Schedules.update);
  });

  // Query fixed cost in isolation: many *distinct* query objects executed per
  // frame, each over the same 16-match set — the "thousands of queries" case.
  final world = World();
  _populate(world, total: 10000, flagged: 16);
  const queryCount = 1000;
  final queries = List<Query1<Stat>>.generate(
    queryCount,
    (_) => world.query1<Stat>(withTypes: const <Type>[Flag]),
    growable: false,
  );
  benchRepeat('$queryCount query executions (16 matches)', queryCount, () {
    for (var i = 0; i < queryCount; i++) {
      queries[i].each((entity, stat) => stat.value += 1);
    }
  });

  // Event maintenance boundary cost. Distinct runtime channel types are not
  // expressible generically, so approximate [channelCount] channels with one
  // channel advanced that many times per run — update() cost is per channel,
  // independent of which type it is.
  final eventWorld = World();
  const channelCount = 64;
  eventWorld.registerEvent<(int, int)>(retainedUpdates: 2);
  final channel = eventWorld.eventChannel<(int, int)>();
  final reader = channel.reader();
  benchRepeat('event update x$channelCount channels', channelCount, () {
    for (var i = 0; i < channelCount; i++) {
      channel.send((i, i));
      reader.consume();
      channel.update();
    }
  });
}
