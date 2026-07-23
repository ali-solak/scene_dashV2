import 'package:scene_dash_v2_core/advanced.dart';
import 'package:test/test.dart';

/// A base shared by two event types, so a `cond ? Pinged() : Ponged()`
/// expression is statically typed as [Signal] — the exact widening that broke
/// static-type-routed dispatch.
sealed class Signal {
  const Signal();
}

final class Pinged extends Signal {
  final int id;
  const Pinged(this.id);
}

final class Ponged extends Signal {
  final int id;
  const Ponged(this.id);
}

void main() {
  group('EventChannel', () {
    test('a reader drains only events sent after it was created', () {
      final channel = EventChannel<Pinged>();
      channel.send(const Pinged(0)); // before reader exists
      final reader = channel.reader();
      channel.send(const Pinged(1));
      channel.send(const Pinged(2));

      expect(reader.drain().map((e) => e.id), <int>[1, 2]);
      expect(reader.drain(), isEmpty, reason: 'cursor advanced');
    });

    test('readers have independent cursors', () {
      final channel = EventChannel<Pinged>();
      final a = channel.reader();
      final b = channel.reader();

      channel.send(const Pinged(1));
      expect(a.drain().map((e) => e.id), <int>[1]);
      // b has not read yet, so it still sees the event.
      expect(b.drain().map((e) => e.id), <int>[1]);
    });

    test('update reclaims events all readers have consumed', () {
      final channel = EventChannel<Pinged>();
      final reader = channel.reader();
      channel.send(const Pinged(1));
      reader.drain();
      channel.update(); // event 1 fully consumed

      channel.send(const Pinged(2));
      expect(reader.drain().map((e) => e.id), <int>[2]);
    });

    test('a slow reader still receives events after update', () {
      final channel = EventChannel<Pinged>();
      final fast = channel.reader();
      final slow = channel.reader();

      channel.send(const Pinged(1));
      fast.drain(); // slow has not read
      channel.update(); // must keep event 1 for slow

      expect(slow.drain().map((e) => e.id), <int>[1]);
    });

    test('the world default retention holds an unread event for eight '
        'passes — the public contract', () {
      final world = World();
      world.registerEvent<Pinged>(); // no retainedUpdates: the default
      final channel = world.eventChannel<Pinged>();
      final stalled = channel.reader();

      channel.send(const Pinged(1));
      for (var pass = 1; pass < 8; pass++) {
        channel.update();
        expect(stalled.hasUnread, isTrue, reason: 'pass $pass of 8');
      }
      channel.update(); // pass 8: the window is spent
      expect(stalled.hasUnread, isFalse);
    });

    test('a stalled reader is skipped past the retention window', () {
      final channel = EventChannel<Pinged>(retainedUpdates: 2);
      final stalled = channel.reader();

      channel.send(const Pinged(1));
      channel.update(); // pass 1: event stays readable (frame N + 1)
      expect(stalled.hasUnread, isTrue);

      channel.update(); // pass 2: retention window exceeded, event expires
      expect(stalled.hasUnread, isFalse);
      expect(stalled.drain(), isEmpty);

      // The channel keeps working normally afterwards.
      channel.send(const Pinged(2));
      expect(stalled.drain().map((e) => e.id), <int>[2]);
    });

    test('a stalled reader cannot grow the buffer without bound', () {
      final channel = EventChannel<Pinged>();
      final active = channel.reader();
      channel.reader(); // stalled: never drains

      for (var frame = 0; frame < 100; frame++) {
        channel.send(Pinged(frame));
        expect(active.drain(), hasLength(1));
        channel.update();
      }
      // Only events inside the retention window can still be buffered.
      channel.send(const Pinged(100));
      expect(active.drain(), hasLength(1));
    });

    test('update reports how many unread events a lagging reader lost', () {
      final channel = EventChannel<Pinged>(retainedUpdates: 2);
      channel.reader(); // never drains

      channel.send(const Pinged(1));
      channel.send(const Pinged(2));
      expect(channel.update(), 0, reason: 'still within the window');
      expect(channel.update(), 2, reason: 'both events expired unread');
      expect(channel.update(), 0, reason: 'nothing new to lose');
    });

    test(
      'null retainedUpdates keeps events until every reader consumed them',
      () {
        final channel = EventChannel<Pinged>(retainedUpdates: null);
        final slow = channel.reader();

        channel.send(const Pinged(1));
        channel.update();
        channel.update();
        channel.update();

        expect(slow.drain().map((e) => e.id), <int>[1]);
      },
    );

    test('retainedUpdates of 1 expires unread events every pass', () {
      final channel = EventChannel<Pinged>(retainedUpdates: 1);
      final reader = channel.reader();

      channel.send(const Pinged(1));
      channel.update();
      expect(reader.hasUnread, isFalse);
    });

    test('writer sends to readers', () {
      final channel = EventChannel<Pinged>();
      final reader = channel.reader();
      channel.writer().send(const Pinged(7));
      expect(reader.drain().map((e) => e.id), <int>[7]);
    });

    test('consume advances the cursor and reports whether any were pending', () {
      final channel = EventChannel<Pinged>();
      final reader = channel.reader();
      expect(reader.consume(), isFalse, reason: 'nothing pending');

      channel
        ..send(const Pinged(1))
        ..send(const Pinged(2));
      expect(reader.consume(), isTrue);
      // Cursor advanced: a second consume in the same window sees nothing, which
      // is what gives once-per-occurrence semantics across a fixed-step loop.
      expect(reader.consume(), isFalse);
      expect(reader.hasUnread, isFalse);
    });

    test('a reader that only drains on fixed steps loses a narrow-retention '
        'event across a zero-step frame', () {
      // The hazard the wide default exists for: an edge is sent between
      // frames, but the reader consumes only on fixed steps. Each frame's
      // updateEvents is a channel.update(); a frame that runs no fixed step
      // is an update() with no intervening drain — under a two-pass window
      // the edge expires before its reader ever gets a turn (the blaster
      // fire-drop; the combat sample's cast keys and wind leap at 144 Hz).
      final channel = EventChannel<Pinged>(retainedUpdates: 2);
      final reader = channel.reader();
      channel.send(const Pinged(1)); // dispatched from a widget between frames

      channel.update(); // frame N+1 frameStart — but no fixed step this frame
      channel.update(); // frame N+2 frameStart
      expect(
        reader.consume(),
        isFalse,
        reason: 'expired before any fixed step read it',
      );
    });

    test('the default retention survives zero-step frames at high refresh', () {
      // The DEFAULT window is several frames wide precisely so a fixed-step
      // reader outlives the zero-step render frames of a high-refresh
      // display: an unread event survives seven maintenance passes and only
      // expires on the eighth.
      final channel = EventChannel<Pinged>();
      final reader = channel.reader();
      channel.send(const Pinged(1));

      for (var pass = 1; pass <= 7; pass++) {
        channel.update();
        expect(
          reader.hasUnread,
          isTrue,
          reason: 'still readable after pass $pass',
        );
      }
      channel.update(); // pass 8: window exceeded
      expect(reader.consume(), isFalse, reason: 'expired unread at pass 8');
    });

    test('null retention keeps an edge until the fixed-step reader takes it', () {
      // The fix: fire edges are registered with retainedUpdates: null, so a
      // release survives any number of zero-step frames until the blaster reads
      // it — held is false, released is true on that step, and the shot fires.
      final channel = EventChannel<Pinged>(retainedUpdates: null);
      final reader = channel.reader();
      channel.send(const Pinged(1));

      channel.update();
      channel.update();
      channel.update();
      expect(reader.consume(), isTrue, reason: 'retained until consumed');
    });

    test('consume leaves other readers untouched', () {
      final channel = EventChannel<Pinged>();
      final a = channel.reader();
      final b = channel.reader();
      channel.send(const Pinged(1));

      expect(a.consume(), isTrue);
      expect(b.drain().map((e) => e.id), <int>[1], reason: 'b still sees it');
    });

    test('forEach reads unread events without affecting other readers', () {
      final channel = EventChannel<Pinged>();
      final a = channel.reader();
      final b = channel.reader();

      channel
        ..send(const Pinged(1))
        ..send(const Pinged(2));

      final seen = <int>[];
      a.forEach((event) => seen.add(event.id));

      expect(seen, <int>[1, 2]);
      expect(a.hasUnread, isFalse);
      expect(b.drain().map((e) => e.id), <int>[1, 2]);
    });

    test('forEach leaves cursor unchanged when callback throws', () {
      final channel = EventChannel<Pinged>();
      final reader = channel.reader();
      channel
        ..send(const Pinged(1))
        ..send(const Pinged(2));

      expect(
        () => reader.forEach((event) {
          if (event.id == 1) throw StateError('boom');
        }),
        throwsStateError,
      );

      expect(reader.drain().map((e) => e.id), <int>[1, 2]);
    });
  });

  group('World event channels', () {
    test('registers and exposes a channel', () {
      final world = World()..registerEvent<Pinged>();
      final reader = world.eventChannel<Pinged>().reader();
      world.eventChannel<Pinged>().send(const Pinged(3));
      expect(reader.drain().map((e) => e.id), <int>[3]);
    });

    test('throws for an unregistered event type', () {
      final world = World();
      expect(world.eventChannel<Pinged>, throwsStateError);
    });

    test(
      'app reports a lagging reader through onDiagnostic, once per type',
      () {
        final messages = <String>[];
        // Explicit two-pass window so the loss (and its report) lands on the
        // second maintenance pass rather than the default window's eighth.
        final app = App(onDiagnostic: messages.add)
          ..addEvent<Pinged>(retainedUpdates: 2);
        app.start();
        app.world.eventChannel<Pinged>().reader(); // never drains

        app.world.eventChannel<Pinged>().send(const Pinged(1));
        app.updateEvents();
        expect(messages, isEmpty, reason: 'still within the window');

        app.updateEvents();
        expect(messages, hasLength(1));
        expect(messages.single, contains('Pinged'));

        app.world.eventChannel<Pinged>().send(const Pinged(2));
        app.updateEvents();
        app.updateEvents();
        expect(messages, hasLength(1), reason: 'reported once per event type');
      },
    );
  });

  group('World.sendEvent (runtime-type routing)', () {
    test('a value typed as a supertype still lands in its concrete channel', () {
      final world = World()
        ..registerEvent<Pinged>()
        ..registerEvent<Ponged>();
      final pings = world.eventChannel<Pinged>().reader();
      final pongs = world.eventChannel<Ponged>().reader();

      // Statically typed as Signal (their common base) — a send that routed by
      // static type would misdeliver both. sendEvent routes by runtime type.
      final Signal a = _pick(true);
      final Signal b = _pick(false);
      world
        ..sendEvent(a)
        ..sendEvent(b);

      expect(pings.drain().map((e) => e.id), <int>[1]);
      expect(pongs.drain().map((e) => e.id), <int>[2]);
    });

    test('throws for an unregistered runtime type', () {
      final world = World();
      expect(() => world.sendEvent(const Pinged(1)), throwsStateError);
    });
  });
}

/// Returns a [Signal] whose static type hides which concrete event it is —
/// mirroring `cond ? Pinged() : Ponged()`.
Signal _pick(bool ping) => ping ? const Pinged(1) : const Ponged(2);
