import 'package:scene_dash_v2_core/advanced.dart';
import 'package:test/test.dart';

/// A minimal hand-written adapter that records when it runs.
final class RecordingAdapter implements SystemAdapter {
  final String name;
  final List<String> log;
  RecordingAdapter(this.name, this.log);

  @override
  void initialize(World world) {}

  @override
  void run() => log.add(name);
}

void main() {
  group('Schedule ordering', () {
    test('runs unconstrained systems in registration order', () {
      final log = <String>[];
      final app = App()
        ..addSystemAdapter(
          RecordingAdapter('a', log),
          schedule: Schedules.update,
          label: const SystemLabel('a'),
        )
        ..addSystemAdapter(
          RecordingAdapter('b', log),
          schedule: Schedules.update,
          label: const SystemLabel('b'),
        );
      app.start();
      app.runSchedule(Schedules.update);
      expect(log, <String>['a', 'b']);
    });

    test('respects after edges', () {
      final log = <String>[];
      final app = App()
        ..addSystemAdapter(
          RecordingAdapter('move', log),
          schedule: Schedules.update,
          label: const SystemLabel('move'),
          after: const [SystemLabel('input')],
        )
        ..addSystemAdapter(
          RecordingAdapter('input', log),
          schedule: Schedules.update,
          label: const SystemLabel('input'),
        );
      app.start();
      app.runSchedule(Schedules.update);
      expect(log, <String>['input', 'move']);
    });

    test('detects duplicate labels at start', () {
      final log = <String>[];
      final app = App()
        ..addSystemAdapter(
          RecordingAdapter('a', log),
          schedule: Schedules.update,
          label: const SystemLabel('dup'),
        )
        ..addSystemAdapter(
          RecordingAdapter('b', log),
          schedule: Schedules.update,
          label: const SystemLabel('dup'),
        );
      expect(app.start, throwsStateError);
    });

    test('detects references to unknown labels at start', () {
      final log = <String>[];
      final app = App()
        ..addSystemAdapter(
          RecordingAdapter('a', log),
          schedule: Schedules.update,
          label: const SystemLabel('a'),
          after: const [SystemLabel('does-not-exist')],
        );
      expect(app.start, throwsStateError);
    });

    test('detects dependency cycles at start', () {
      final log = <String>[];
      final app = App()
        ..addSystemAdapter(
          RecordingAdapter('a', log),
          schedule: Schedules.update,
          label: const SystemLabel('a'),
          after: const [SystemLabel('b')],
        )
        ..addSystemAdapter(
          RecordingAdapter('b', log),
          schedule: Schedules.update,
          label: const SystemLabel('b'),
          after: const [SystemLabel('a')],
        );
      expect(app.start, throwsStateError);
    });

    test('rejects registering systems after start', () {
      final app = App()..start();
      expect(
        () => app.addSystemAdapter(
          RecordingAdapter('late', <String>[]),
          schedule: Schedules.update,
          label: const SystemLabel('late'),
        ),
        throwsStateError,
      );
    });

    test('rejects builder mutations after start', () {
      final app = App()..start();

      expect(() => app.addPlugin(const _EmptyPlugin()), throwsStateError);
      expect(app.addEvent<String>, throwsStateError);
      expect(() => app.insertResource<Object>(Object()), throwsStateError);
      expect(() => app.addCleanup(() {}), throwsStateError);
    });

    test('runIf skips a system while false and is re-evaluated every run', () {
      final log = <String>[];
      final app = App()
        ..insertResource<_Gate>(_Gate())
        ..addSystemAdapter(
          RecordingAdapter('gated', log),
          schedule: Schedules.update,
          label: const SystemLabel('gated'),
          runIf: (world) => world.resource<_Gate>().open,
        )
        ..addSystemAdapter(
          RecordingAdapter('always', log),
          schedule: Schedules.update,
          label: const SystemLabel('always'),
        );
      app.start();

      app.runSchedule(Schedules.update);
      expect(log, <String>['always'], reason: 'gate closed: system skipped');

      app.world.resource<_Gate>().open = true;
      app.runSchedule(Schedules.update);
      expect(log, <String>['always', 'gated', 'always']);

      app.world.resource<_Gate>().open = false;
      app.runSchedule(Schedules.update);
      expect(log, <String>['always', 'gated', 'always', 'always']);
    });

    test('runIf works through addSystem descriptors and with the profiler',
        () {
      final log = <String>[];
      final app = App(
        diagnostics: const AppDiagnostics(profileSystems: true),
      )
        ..addSystemAdapter(
          RecordingAdapter('never', log),
          schedule: Schedules.update,
          label: const SystemLabel('never'),
          runIf: (world) => false,
        );
      app.start();
      app.runSchedule(Schedules.update);

      expect(log, isEmpty);
      expect(
        app.profiler!.timingOf(const SystemLabel('never'), Schedules.update),
        isNull,
        reason: 'a skipped system is not timed',
      );
    });

    test('shutdown runs schedule then async cleanups once in reverse order',
        () async {
      final log = <String>[];
      final app = App()
        ..addSystemAdapter(
          RecordingAdapter('shutdown', log),
          schedule: Schedules.shutdown,
          label: const SystemLabel('shutdown.probe'),
        )
        ..addCleanup(() async {
          await Future<void>.delayed(Duration.zero);
          log.add('cleanup-a');
        })
        ..addCleanup(() {
          log.add('cleanup-b');
        });

      app.start();
      await app.shutdown();
      await app.shutdown();

      expect(log, <String>['shutdown', 'cleanup-b', 'cleanup-a']);
    });
  });

  group('addSystems (batch registration)', () {
    SystemDescriptor descriptor(String name, List<String> log) =>
        SystemDescriptor(
          SystemRef('package:test/batch.dart', name),
          () => RecordingAdapter(name, log),
        );

    test('registers every descriptor into the schedule', () {
      final log = <String>[];
      final app = App()
        ..addSystems(Schedules.update, [
          descriptor('a', log),
          descriptor('b', log),
          descriptor('c', log),
        ]);
      app.start();
      app.runSchedule(Schedules.update);
      expect(log, <String>['a', 'b', 'c']);
    });

    test('chained adds sequential after constraints', () {
      final log = <String>[];
      final a = descriptor('a', log);
      final b = descriptor('b', log);
      // Registration order alone would also run a -> b, so prove the edge is
      // real: an explicit contradictory constraint must now form a cycle.
      final app = App()
        ..addSystems(Schedules.update, [a, b], chained: true)
        ..addSystem(
          descriptor('straggler', log),
          schedule: Schedules.update,
          after: [b],
          before: [a],
        );
      expect(app.start, throwsStateError);
    });

    test('set order overrides registration order across features', () {
      const early = SystemSet('early');
      const late_ = SystemSet('late');
      final log = <String>[];
      // Registered in the "wrong" order; the set chain must flip them.
      final app = App()
        ..addSystemAdapter(
          RecordingAdapter('reaction', log),
          schedule: Schedules.update,
          label: const SystemLabel('reaction'),
          inSet: late_,
        )
        ..addSystemAdapter(
          RecordingAdapter('logic', log),
          schedule: Schedules.update,
          label: const SystemLabel('logic'),
          inSet: early,
        )
        ..configureSets(Schedules.update, [early, late_]);
      app.start();
      app.runSchedule(Schedules.update);
      expect(log, <String>['logic', 'reaction']);
    });

    test('an empty set never breaks the chain', () {
      const first = SystemSet('first');
      const emptyPhase = SystemSet('empty');
      const last = SystemSet('last');
      final log = <String>[];
      final app = App()
        ..configureSets(Schedules.update, [first, emptyPhase, last])
        ..addSystemAdapter(
          RecordingAdapter('z', log),
          schedule: Schedules.update,
          label: const SystemLabel('z'),
          inSet: last,
        )
        ..addSystemAdapter(
          RecordingAdapter('a', log),
          schedule: Schedules.update,
          label: const SystemLabel('a'),
          inSet: first,
        );
      app.start();
      app.runSchedule(Schedules.update);
      expect(log, <String>['a', 'z'],
          reason: 'first still orders before last across the empty phase');
    });

    test('set membership without configuration is inert', () {
      final log = <String>[];
      final app = App()
        ..addSystemAdapter(
          RecordingAdapter('a', log),
          schedule: Schedules.update,
          label: const SystemLabel('a'),
          inSet: const SystemSet('unconfigured'),
        );
      app.start();
      app.runSchedule(Schedules.update);
      expect(log, <String>['a']);
    });

    test('set edges participate in cycle detection', () {
      const first = SystemSet('first');
      const second = SystemSet('second');
      final log = <String>[];
      final app = App()
        ..configureSets(Schedules.update, [first, second])
        ..addSystemAdapter(
          RecordingAdapter('a', log),
          schedule: Schedules.update,
          label: const SystemLabel('a'),
          inSet: first,
        )
        ..addSystemAdapter(
          RecordingAdapter('b', log),
          schedule: Schedules.update,
          label: const SystemLabel('b'),
          inSet: second,
          // Contradicts the set chain: b must be before a AND after it.
          before: const [SystemLabel('a')],
        );
      expect(app.start, throwsStateError);
    });

    test('one runIf gates the whole batch', () {
      final log = <String>[];
      final gate = _Gate();
      final app = App()
        ..insertResource<_Gate>(gate)
        ..addSystems(
          Schedules.update,
          [descriptor('a', log), descriptor('b', log)],
          runIf: (world) => world.resource<_Gate>().open,
        );
      app.start();
      app.runSchedule(Schedules.update);
      expect(log, isEmpty);

      gate.open = true;
      app.runSchedule(Schedules.update);
      expect(log, <String>['a', 'b']);
    });
  });
}

final class _EmptyPlugin extends Plugin {
  const _EmptyPlugin();

  @override
  void build(AppBuilder app) {}
}

final class _Gate {
  bool open = false;
}
