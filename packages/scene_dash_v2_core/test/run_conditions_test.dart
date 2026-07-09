import 'package:scene_dash_v2_core/advanced.dart';
import 'package:test/test.dart';

final class Flag {
  bool value = false;
}

bool _flagSet(World world) => world.resource<Flag>().value;

void main() {
  late World world;

  setUp(() {
    world = World()..resources.insert(Flag());
  });

  test('not inverts a condition', () {
    expect(not(_flagSet)(world), isTrue);
    world.resource<Flag>().value = true;
    expect(not(_flagSet)(world), isFalse);
  });

  test('and passes only when both pass, and short-circuits', () {
    var evaluated = false;
    bool probe(World _) {
      evaluated = true;
      return true;
    }

    final both = _flagSet.and(probe);
    expect(both(world), isFalse);
    expect(evaluated, isFalse, reason: 'right side skipped when left fails');

    world.resource<Flag>().value = true;
    expect(both(world), isTrue);
    expect(evaluated, isTrue);
  });

  test('or passes when either passes, and short-circuits', () {
    var evaluated = false;
    bool probe(World _) {
      evaluated = true;
      return false;
    }

    world.resource<Flag>().value = true;
    final either = _flagSet.or(probe);
    expect(either(world), isTrue);
    expect(evaluated, isFalse, reason: 'right side skipped when left passes');

    world.resource<Flag>().value = false;
    expect(either(world), isFalse);
    expect(evaluated, isTrue);
  });

  test('hasEvents tracks the channel buffer', () {
    world.registerEvent<String>();
    final condition = hasEvents<String>();

    expect(condition(world), isFalse);
    world.eventChannel<String>().send('hit');
    expect(condition(world), isTrue);

    // v2: with no readers, maintenance expires by the retention window —
    // per-registration cursors are created lazily on a system's first run,
    // so fresh events must survive to it — then drops.
    world.updateEvents();
    expect(condition(world), isTrue);
    world.updateEvents();
    expect(condition(world), isFalse);
  });

  test('hasEvents holds unread events through the retention window', () {
    world.registerEvent<String>();
    // A registered reader that does not drain: the event survives the pass
    // for the frame it was sent plus one more (default retention of 2),
    // then expires.
    world.eventChannel<String>().reader();
    final condition = hasEvents<String>();

    world.eventChannel<String>().send('hit');
    world.updateEvents();
    expect(condition(world), isTrue);
    world.updateEvents();
    expect(condition(world), isFalse);
  });

  test('hasEvents on an unregistered channel fails loudly', () {
    expect(() => hasEvents<int>()(world), throwsStateError);
  });

  group('every', () {
    late FrameTime time;

    setUp(() {
      time = FrameTime();
      world.resources.insert(time);
    });

    /// Evaluates [condition] once with a frame delta of [delta] seconds.
    bool tick(RunCondition condition, double delta) {
      time.delta = delta;
      return condition(world);
    }

    test('fires after one full period, not immediately', () {
      final condition = every(0.3);
      expect(tick(condition, 0), isFalse);
      expect(tick(condition, 0.1), isFalse);
      expect(tick(condition, 0.1), isFalse);
      expect(tick(condition, 0.1), isTrue, reason: '0.3s accumulated');
      expect(tick(condition, 0.1), isFalse, reason: 'next period restarts');
    });

    test('does not drift: the overshoot carries into the next period', () {
      final condition = every(0.1);
      // 201 ticks of 0.05s = 10.05s of game time at a 0.1s period.
      var fires = 0;
      for (var i = 0; i < 201; i++) {
        if (tick(condition, 0.05)) fires++;
      }
      expect(fires, 100, reason: '10.05s / 0.1s, the odd 0.05 carries over');
    });

    test('a leftover above the period keeps firing on later evaluations', () {
      final condition = every(0.1);
      // One hitched frame worth several periods: fires once now, and the
      // surplus drains one fire per subsequent evaluation instead of being
      // dropped.
      expect(tick(condition, 0.35), isTrue);
      expect(tick(condition, 0), isTrue);
      expect(tick(condition, 0), isTrue);
      expect(tick(condition, 0), isFalse, reason: '0.05 left, below period');
    });

    test('each registration gets an independent accumulator', () {
      final a = every(0.2);
      final b = every(0.2);

      expect(tick(a, 0.15), isFalse);
      // Only a has accumulated: b starts from zero on its first evaluation.
      expect(tick(b, 0.05), isFalse);
      expect(tick(a, 0.05), isTrue);
      expect(tick(b, 0.05), isFalse);
    });

    test('composes with other conditions', () {
      world.resource<Flag>().value = true;
      final gated = every(0.1).and(_flagSet);

      expect(tick(gated, 0.1), isTrue);
      world.resource<Flag>().value = false;
      expect(tick(gated, 0.1), isFalse, reason: 'period elapsed but gated');
    });
  });
}
