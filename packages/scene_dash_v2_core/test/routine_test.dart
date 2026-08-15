import 'package:scene_dash_v2_core/scene_dash_v2_core.dart';
import 'package:test/test.dart';

/// A game's leaf vocabulary: a sealed family rooted in Step.
sealed class TestStep extends Step<TestStep> {
  const TestStep();
}

/// Settles instantly.
final class Beat extends TestStep {
  const Beat(this.id);
  final String id;
  @override
  String toString() => id;
}

/// Runs until [seconds] have passed.
final class Hold extends TestStep {
  const Hold(this.seconds);
  final double seconds;
  @override
  String toString() => 'Hold ${seconds}s';
}

/// Always fails.
final class Boom extends TestStep {
  const Boom();
  @override
  String toString() => 'Boom';
}

/// A driver: records every leaf it visits and reports a result per leaf type.
/// The switch is exhaustive with no default, which is the compile-time check
/// that composites never reach a driver.
StepResult Function(TestStep) driver(
  Routine<TestStep> routine,
  List<String> log,
) {
  return (leaf) {
    log.add('$leaf');
    return switch (leaf) {
      Beat() => StepResult.success,
      Hold(:final seconds) =>
        routine.elapsed >= seconds ? StepResult.success : StepResult.running,
      Boom() => StepResult.failure,
    };
  };
}

/// A leaf with no toString override, like most real ones.
final class Plain extends Step<Plain> {
  const Plain();
}

void main() {
  group('Routine cursor', () {
    test('a sequence of instant leaves settles in one advance, in order', () {
      final routine = Routine<TestStep>(
        const Sequence([Beat('a'), Beat('b'), Beat('c')]),
      );
      final log = <String>[];
      routine.advance(0, driver(routine, log));

      expect(log, ['a', 'b', 'c']);
      expect(routine.finished, isTrue);
      expect(routine.failed, isFalse);
      expect(routine.current, isNull);
    });

    test('running holds the cursor while elapsed accumulates', () {
      final routine = Routine<TestStep>(
        const Sequence([Hold(1.0), Beat('done')]),
      );
      final log = <String>[];

      routine.advance(0.4, driver(routine, log));
      expect(routine.current, isA<Hold>(), reason: 'still waiting');
      expect(routine.elapsed, closeTo(0.4, 1e-9));

      routine.advance(0.4, driver(routine, log));
      expect(routine.current, isA<Hold>());
      expect(routine.elapsed, closeTo(0.8, 1e-9));
      expect(routine.finished, isFalse);

      routine.advance(0.4, driver(routine, log));
      expect(log.last, 'done');
      expect(routine.finished, isTrue);
    });

    test('a cursor move zeroes elapsed', () {
      final routine = Routine<TestStep>(const Sequence([Hold(0.5), Hold(10)]));
      routine.advance(0.6, driver(routine, <String>[]));

      expect(routine.current, isA<Hold>());
      expect((routine.current! as Hold).seconds, 10, reason: 'the second hold');
      expect(routine.elapsed, 0, reason: 'the new leaf starts fresh');
    });

    test('advance is a no-op once finished', () {
      final routine = Routine<TestStep>(const Sequence([Beat('a')]));
      final log = <String>[];
      routine.advance(0, driver(routine, log));
      routine.advance(1, driver(routine, log));

      expect(log, ['a'], reason: 'the second advance visited nothing');
      expect(routine.elapsed, 0, reason: 'and did not accumulate time');
    });

    test('restart returns the cursor to the start', () {
      final routine = Routine<TestStep>(const Sequence([Beat('a'), Hold(5)]));
      routine.advance(1, driver(routine, <String>[]));
      expect(routine.current, isA<Hold>());
      expect(routine.elapsed, 0);

      routine.restart();
      expect(routine.current, isA<Beat>());
      expect(routine.finished, isFalse);
    });
  });

  group('Routine composites', () {
    test('Repeat runs its child exactly times times, then succeeds', () {
      final routine = Routine<TestStep>(const Repeat(Beat('x'), times: 3));
      final log = <String>[];
      routine.advance(0, driver(routine, log));

      expect(log, ['x', 'x', 'x']);
      expect(routine.finished, isTrue);
      expect(routine.failed, isFalse);
    });

    test('Repeat with a null times runs until maxSteps, then asserts', () {
      final routine = Routine<TestStep>(const Repeat(Beat('x')));
      expect(
        () => routine.advance(0, driver(routine, <String>[])),
        throwsA(isA<AssertionError>()),
        reason: 'a Repeat of instantaneous leaves can never yield',
      );
    });

    test('Repeat forever is fine when its child takes time', () {
      final routine = Routine<TestStep>(const Repeat(Hold(1.0)));
      final log = <String>[];

      routine.advance(1.5, driver(routine, log));
      expect(routine.finished, isFalse, reason: 'loops forever');
      expect(routine.loops.first, 1, reason: 'one iteration banked');
      expect(
        log.length,
        2,
        reason: 'the hold completed, then the next one was offered and held',
      );
      expect(routine.elapsed, 0, reason: 'the new iteration starts fresh');
    });

    test('Select takes the next child after one fails', () {
      final routine = Routine<TestStep>(
        const Select([Boom(), Beat('fallback')]),
      );
      final log = <String>[];
      routine.advance(0, driver(routine, log));

      expect(log, ['Boom', 'fallback']);
      expect(routine.finished, isTrue);
      expect(routine.failed, isFalse, reason: 'the fallback succeeded');
    });

    test('Select fails when every child fails', () {
      final routine = Routine<TestStep>(const Select([Boom(), Boom()]));
      routine.advance(0, driver(routine, <String>[]));

      expect(routine.finished, isTrue);
      expect(routine.failed, isTrue);
    });

    test('failure unwinds a Sequence to the root and skips the rest', () {
      final routine = Routine<TestStep>(
        const Sequence([Beat('a'), Boom(), Beat('never')]),
      );
      final log = <String>[];
      routine.advance(0, driver(routine, log));

      expect(log, ['a', 'Boom']);
      expect(routine.failed, isTrue);
      expect(routine.current, isNull);
    });

    test(
      'failure propagates through Repeat without consuming an iteration',
      () {
        final routine = Routine<TestStep>(
          const Repeat(Sequence([Beat('a'), Boom()]), times: 3),
        );
        final log = <String>[];
        routine.advance(0, driver(routine, log));

        expect(log, ['a', 'Boom'], reason: 'the second iteration never starts');
        expect(routine.failed, isTrue);
      },
    );

    test('an empty Sequence succeeds and an empty Select fails', () {
      final ok = Routine<TestStep>(const Sequence([]));
      expect(ok.finished, isTrue);
      expect(ok.failed, isFalse);

      final bad = Routine<TestStep>(const Select([]));
      expect(bad.finished, isTrue);
      expect(bad.failed, isTrue);
    });

    test('a bare leaf is a valid plan', () {
      final routine = Routine<TestStep>(const Beat('only'));
      final log = <String>[];
      routine.advance(0, driver(routine, log));

      expect(log, ['only']);
      expect(routine.finished, isTrue);
    });
  });

  group('Routine save and resume', () {
    test('path, loops and elapsed round-trip mid-plan', () {
      const plan = Repeat<TestStep>(
        Sequence([Beat('a'), Hold(2.0), Beat('c')]),
        times: 4,
      );
      final live = Routine<TestStep>(plan);
      live.advance(0.75, driver(live, <String>[]));

      // The whole save payload: two int lists and a double.
      final saved = Routine<TestStep>.resume(
        plan,
        path: live.path,
        loops: live.loops,
        elapsed: live.elapsed,
      );

      expect(saved.path, live.path);
      expect(saved.loops, live.loops);
      expect(saved.elapsed, live.elapsed);
      expect('${saved.current}', '${live.current}');

      // And it keeps running from there, rolling into the next iteration.
      final log = <String>[];
      saved.advance(2.5, driver(saved, log));
      expect(log, ['Hold 2.0s', 'c', 'a', 'Hold 2.0s']);
      expect(saved.loops.first, 1, reason: 'one lap of the Repeat banked');
    });
  });

  group('Routine toString', () {
    test('renders the active path, the leaf and its elapsed time', () {
      final routine = Routine<TestStep>(
        const Repeat(Sequence([Hold(2.0)]), times: 2),
      );
      routine.advance(0.42, driver(routine, <String>[]));

      expect('$routine', 'Repeat[0] Sequence[0] Hold 2.0s (0.42s)');
    });

    test('falls back to the type name when a leaf has no toString', () {
      final routine = Routine<Plain>(const Sequence([Plain()]));
      expect('$routine', 'Sequence[0] Plain (0.00s)');
    });

    test('reports the outcome once settled', () {
      final done = Routine<TestStep>(const Sequence([Beat('a')]))
        ..advance(0, (_) => StepResult.success);
      expect('$done', 'finished');

      final dead = Routine<TestStep>(const Sequence([Boom()]))
        ..advance(0, (_) => StepResult.failure);
      expect('$dead', 'failed');
    });
  });
}
