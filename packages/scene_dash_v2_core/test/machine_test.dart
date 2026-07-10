import 'package:scene_dash_v2_core/scene_dash_v2_core.dart';
import 'package:test/test.dart';

enum Phase { idle, startup, active, recovery }

/// Edge-exactness coverage for [Machine] — every consequence of the M2
/// latch rule by name. The latch is the whole design: `go()` raises edges
/// immediately, the next `tick()` lowers them, so an edge is true for
/// exactly one tick-window (`GameTimer.justFinished` semantics for modes).
void main() {
  group('Machine edge latch', () {
    test('go-then-tick visibility window: edges are true from go until '
        'the next tick', () {
      final m = Machine<Phase>(Phase.idle);
      m.go(Phase.startup);
      expect(m.justEntered(Phase.startup), isTrue);
      expect(m.justExited(Phase.idle), isTrue);
      m.tick(1 / 60);
      expect(m.justEntered(Phase.startup), isFalse);
      expect(m.justExited(Phase.idle), isFalse);
    });

    test('a transition inside the owning tick-window stays visible to a '
        'later reader the same frame', () {
      final m = Machine<Phase>(Phase.idle);
      // The owner's frame: tick first, then transition in its switch.
      m.tick(1 / 60);
      m.go(Phase.startup);
      // A later system this frame reads the edge.
      expect(m.justEntered(Phase.startup), isTrue);
      // The owner's next frame begins with its tick: the window closes.
      m.tick(1 / 60);
      expect(m.justEntered(Phase.startup), isFalse);
    });

    test('an edge clears after exactly one subsequent tick', () {
      final m = Machine<Phase>(Phase.idle)..go(Phase.active);
      expect(m.justEntered(Phase.active), isTrue, reason: 'zero ticks: up');
      m.tick(0);
      expect(m.justEntered(Phase.active), isFalse, reason: 'one tick: down');
      m.tick(0);
      expect(m.justEntered(Phase.active), isFalse);
    });

    test('same-state go is fully inert: no edges, inState preserved', () {
      final m = Machine<Phase>(Phase.idle)..tick(0.5);
      m.go(Phase.idle);
      expect(m.justEntered(Phase.idle), isFalse);
      expect(m.justExited(Phase.idle), isFalse);
      expect(m.inState, 0.5, reason: 'not reset by a same-state go');
    });

    test('multiple gos in one window: the final entry and the last exit '
        'remain; intermediates are not tracked', () {
      final m = Machine<Phase>(Phase.idle);
      m.go(Phase.startup);
      m.go(Phase.active);
      expect(m.justEntered(Phase.active), isTrue);
      expect(m.justEntered(Phase.startup), isFalse,
          reason: 'intermediate entry lost');
      expect(m.justExited(Phase.startup), isTrue,
          reason: 'the LAST exit (startup -> active)');
      expect(m.justExited(Phase.idle), isFalse,
          reason: 'the earlier exit is not tracked');
    });

    test('justExited pairs with the state most recently left', () {
      final m = Machine<Phase>(Phase.startup)..go(Phase.active);
      expect(m.justExited(Phase.startup), isTrue);
      expect(m.justExited(Phase.active), isFalse);
      m.tick(0);
      m.go(Phase.recovery);
      expect(m.justExited(Phase.active), isTrue);
      expect(m.justExited(Phase.startup), isFalse);
    });
  });

  group('Machine time', () {
    test('inState accumulates the owner-passed dt and go zeroes it', () {
      final m = Machine<Phase>(Phase.idle);
      // A scripted dt sequence: normal steps, a freeze (dt 0, exactly what
      // the fixed loop delivers under pause/hitstop: no ticks at all — the
      // zero here doubles as "a tick that adds nothing"), slow motion.
      m.tick(0.5);
      m.tick(0);
      m.tick(0.25);
      expect(m.inState, 0.75);
      m.go(Phase.startup);
      expect(m.inState, 0, reason: 'go zeroes the state clock');
      m.tick(0.1);
      expect(m.inState, 0.1);
    });
  });

  group('Machine toString', () {
    test('renders the enum value name and the seconds in state', () {
      final m = Machine<Phase>(Phase.startup)..tick(0.42);
      expect('$m', 'startup (0.42s)');
      m.go(Phase.active);
      expect('$m', 'active (0.00s)');
    });
  });
}
