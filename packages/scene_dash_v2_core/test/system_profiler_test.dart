import 'package:scene_dash_v2_core/advanced.dart';
import 'package:test/test.dart';

/// A no-op adapter, used to verify run counting.
final class _NoopAdapter implements SystemAdapter {
  @override
  void initialize(World world) {}

  @override
  void run() {}
}

/// An adapter that busy-spins for [micros] microseconds, so a run reliably
/// exceeds a small slow-system threshold.
final class _SpinAdapter implements SystemAdapter {
  _SpinAdapter(this.micros);
  final int micros;

  @override
  void initialize(World world) {}

  @override
  void run() {
    final sw = Stopwatch()..start();
    while (sw.elapsedMicroseconds < micros) {
      // Busy wait.
    }
  }
}

void main() {
  group('System profiling', () {
    test('is disabled by default (no profiler, near-zero overhead path)', () {
      final app = App()
        ..addSystemAdapter(
          _NoopAdapter(),
          schedule: Schedules.update,
          label: const SystemLabel('noop'),
        );
      app.start();
      expect(app.profiler, isNull);
      expect(app.world.resources.contains<SystemProfiler>(), isFalse);
    });

    test(
      'records per-system timings and exposes the profiler as a resource',
      () {
        final app = App(diagnostics: const AppDiagnostics(profileSystems: true))
          ..addSystemAdapter(
            _NoopAdapter(),
            schedule: Schedules.update,
            label: const SystemLabel('pkg#move'),
          );
        app.start();

        final profiler = app.profiler;
        expect(profiler, isNotNull);
        expect(
          app.world.resources.get<SystemProfiler>(),
          same(profiler),
          reason: 'the profiler is injectable as a resource',
        );

        profiler!.beginFrame();
        app.runSchedule(Schedules.update);
        app.runSchedule(Schedules.update);

        final timing = profiler.timingOf(
          const SystemLabel('pkg#move'),
          Schedules.update,
        );
        expect(timing, isNotNull);
        expect(timing!.runs, 2);
        expect(
          timing.debugName,
          'move',
          reason: 'short name after the # marker',
        );
        expect(timing.schedule, Schedules.update);
        expect(timing.lastFrame, profiler.frame);
        expect(timing.maximum >= timing.latest, isTrue);
        expect(timing.total >= timing.latest, isTrue);
      },
    );

    test('reuses one timing record for steady-state runs', () {
      final app = App(diagnostics: const AppDiagnostics(profileSystems: true))
        ..addSystemAdapter(
          _NoopAdapter(),
          schedule: Schedules.update,
          label: const SystemLabel('pkg#stable'),
        );
      app.start();

      app.runSchedule(Schedules.update);
      final first = app.profiler!.timingOf(
        const SystemLabel('pkg#stable'),
        Schedules.update,
      );

      app.runSchedule(Schedules.update);
      final second = app.profiler!.timingOf(
        const SystemLabel('pkg#stable'),
        Schedules.update,
      );

      expect(second, same(first));
      expect(second!.runs, 2);
      expect(app.profiler!.timings, hasLength(1));
    });

    test('warns when a system exceeds the slow-system threshold', () {
      final slow = <SlowSystemEvent>[];
      final app =
          App(
              diagnostics: AppDiagnostics(
                profileSystems: true,
                slowSystemThreshold: const Duration(milliseconds: 1),
                onSlowSystem: slow.add,
              ),
            )
            ..addSystemAdapter(
              _SpinAdapter(4000),
              schedule: Schedules.update,
              label: const SystemLabel('pkg#expensive'),
            )
            ..addSystemAdapter(
              _NoopAdapter(),
              schedule: Schedules.update,
              label: const SystemLabel('pkg#cheap'),
            );
      app.start();
      app.runSchedule(Schedules.update);

      expect(slow, hasLength(1), reason: 'only the spinning system is slow');
      expect(slow.single.timing.debugName, 'expensive');
      expect(slow.single.elapsed.inMilliseconds >= 1, isTrue);
    });

    test('reset clears timings and the frame counter', () {
      final app = App(diagnostics: const AppDiagnostics(profileSystems: true))
        ..addSystemAdapter(
          _NoopAdapter(),
          schedule: Schedules.update,
          label: const SystemLabel('pkg#move'),
        );
      app.start();
      app.profiler!
        ..beginFrame()
        ..reset();
      app.runSchedule(Schedules.update);

      expect(app.profiler!.frame, 0);
      // A run after reset re-creates the record from scratch.
      expect(
        app.profiler!
            .timingOf(const SystemLabel('pkg#move'), Schedules.update)!
            .runs,
        1,
      );
    });

    test('keeps a separate record per schedule for the same system', () {
      const shared = SystemLabel('pkg#shared');
      final app = App(diagnostics: const AppDiagnostics(profileSystems: true))
        ..addSystemAdapter(
          _NoopAdapter(),
          schedule: Schedules.update,
          label: shared,
        )
        ..addSystemAdapter(
          _NoopAdapter(),
          schedule: Schedules.fixedPrePhysics,
          label: shared,
        );
      app.start();
      app.runSchedule(Schedules.update);
      app.runSchedule(Schedules.update);
      app.runSchedule(Schedules.fixedPrePhysics);

      final profiler = app.profiler!;
      expect(profiler.timingOf(shared, Schedules.update)!.runs, 2);
      expect(profiler.timingOf(shared, Schedules.fixedPrePhysics)!.runs, 1);
      expect(profiler.timings, hasLength(2), reason: 'one record per schedule');
    });
  });
}
