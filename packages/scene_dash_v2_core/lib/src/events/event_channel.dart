/// The non-generic maintenance surface of an [EventChannel].
///
/// The world stores channels behind this interface so it can advance them each
/// frame with a direct (non-dynamic) call regardless of their event type.
abstract interface class EventChannelMaintenance {
  /// Reclaims consumed events; see [EventChannel.update].
  ///
  /// Returns the largest number of unread events any single reader lost to
  /// the retention window this pass (`0` when no reader fell behind).
  int update();

  /// Number of events currently buffered (sent but not yet reclaimed).
  /// Diagnostics surface — the inspector snapshot reads it.
  int get pendingCount;

  /// Whether the most recent [update] found a reader that lost events to
  /// the retention window. Diagnostics surface — the inspector snapshot
  /// reads it; cleared by the next pass where nobody falls behind.
  bool get readerLagged;

  /// Appends [event] without a static type argument. Used by [World.sendEvent]
  /// to route an event to the channel for its *runtime* type, so a
  /// statically-widened value still lands in the right channel. Throws if
  /// [event] is not an instance of this channel's event type.
  void sendDynamic(Object event);

  /// Discards every buffered event; see [EventChannel.clear].
  void clear();
}

/// A buffered, multi-reader event channel for events of type [T].
///
/// Events are appended by writers and read by any number of [EventReader]s,
/// each of which keeps its own independent cursor. One reader consuming events
/// never advances another reader's cursor.
///
/// [update] reclaims the prefix of events that every registered reader has
/// already observed, so the buffer does not grow without bound.
///
/// ## Retention
///
/// A reader that stops draining (a system that early-returns while the game is
/// paused, for example) would otherwise pin the buffer forever. Each event is
/// therefore kept for at most [retainedUpdates] maintenance passes: readers
/// that lag further behind skip the dropped events instead of leaking memory.
///
/// The default of `8` is deliberately wider than Bevy's two-frame window,
/// because maintenance runs once per RENDER frame while fixed-step systems
/// only run when the fixed accumulator fills: at high refresh rates a render
/// frame can carry ZERO fixed steps, and under a two-pass window an input
/// edge could expire before its fixed-step reader ever got a turn — a cast
/// key that "sometimes needs two presses" on a 144 Hz desktop and never
/// fails on a slow phone. Eight passes keeps events alive across the
/// zero-step frames of any realistic display while still expiring what
/// nobody reads. Systems that read their channels every frame never miss
/// anything at any setting. Pass `null` to retain events until every reader
/// has consumed them, however long that takes.
final class EventChannel<T> implements EventChannelMaintenance {
  /// Creates a channel that keeps unread events for at most [retainedUpdates]
  /// calls to [update], or indefinitely when [retainedUpdates] is `null`.
  EventChannel({this.retainedUpdates = 8})
    : assert(
        retainedUpdates == null || retainedUpdates >= 1,
        'retainedUpdates must be at least 1 (or null for unbounded).',
      );

  /// How many maintenance passes an unread event survives, or `null` for
  /// unbounded retention.
  final int? retainedUpdates;

  final List<T> _events = <T>[];

  /// Absolute index of `_events[0]` in the channel's lifetime numbering.
  int _base = 0;

  final List<EventReader<T>> _readers = <EventReader<T>>[];

  /// The channel end (`_end`) recorded at each of the last
  /// `retainedUpdates - 1` maintenance passes, oldest first. Empty when
  /// retention is unbounded (or the window is a single pass).
  final List<int> _retainedEnds = <int>[];

  /// Absolute index just past the last event (one more than the newest).
  int get _end => _base + _events.length;

  bool _readerLagged = false;

  @override
  int get pendingCount => _events.length;

  @override
  bool get readerLagged => _readerLagged;

  /// Whether the channel currently buffers any events. An event stays
  /// buffered until every reader has consumed it, capped by the retention
  /// window (see [EventChannel] docs) — at most [retainedUpdates]
  /// maintenance passes after it was sent. The `hasEvents` run condition
  /// keys off this.
  bool get isNotEmpty => _events.isNotEmpty;

  /// Whether the channel buffers no events. See [isNotEmpty].
  bool get isEmpty => _events.isEmpty;

  /// Whether any reader is registered on this channel. Producers that do
  /// non-trivial work per event (the physics entity-resolution bridge, for
  /// example) key off this to skip production entirely while nothing
  /// consumes — a reader-less channel would expire the events unread
  /// anyway.
  bool get hasReaders => _readers.isNotEmpty;

  /// Appends an event to the channel.
  void send(T event) => _events.add(event);

  @override
  void sendDynamic(Object event) => send(event as T);

  /// Creates a reader positioned at the current end (it will only observe
  /// events sent after this call).
  EventReader<T> reader() {
    final reader = EventReader<T>._(this).._cursor = _end;
    _readers.add(reader);
    return reader;
  }

  /// Creates a reader positioned at the oldest still-buffered event, so it
  /// also observes events sent before this call (bounded by the retention
  /// window). The v2 surface uses this for lazily-created per-registration
  /// cursors, which must not miss events emitted just before a system's
  /// first run.
  EventReader<T> readerFromStart() {
    final reader = EventReader<T>._(this).._cursor = _base;
    _readers.add(reader);
    return reader;
  }

  /// Creates a writer bound to this channel.
  EventWriter<T> writer() => EventWriter<T>._(this);

  /// Discards every buffered event, read or not — the event side of
  /// `World.reset`.
  ///
  /// Every reader's cursor is snapped to the new end, so readers created
  /// before the clear stay registered and simply observe nothing until new
  /// events arrive; the retention window restarts empty. Unlike [update],
  /// nothing is delivered or counted as skipped — cleared events were
  /// deliberately discarded, not lost to lag.
  @override
  void clear() {
    final end = _end;
    _events.clear();
    _base = end;
    for (final reader in _readers) {
      reader._cursor = end;
    }
    _retainedEnds.clear();
  }

  /// Drops the prefix of events that all readers have already consumed, and
  /// force-expires events older than the retention window (see [EventChannel]
  /// docs) so a stalled reader cannot pin the buffer.
  ///
  /// If there are no readers, every event is dropped.
  ///
  /// Returns the largest number of unread events any single reader lost to
  /// the retention window this pass (`0` when nobody fell behind), so the app
  /// can surface a diagnostic for readers that skip frames.
  @override
  int update() {
    _readerLagged = false;
    if (_readers.isEmpty) {
      // v2: a channel can exist before its first reader (per-registration
      // cursors are created lazily on a system's first run), so a
      // reader-less channel expires by the retention window like any lagging
      // reader would — events emitted just before that first run survive to
      // it. Unbounded retention with no readers would leak, so that case
      // keeps the original drop-everything behavior.
      final maxPasses = retainedUpdates;
      if (maxPasses == null) {
        _base = _end;
        _events.clear();
        _retainedEnds.clear();
        return 0;
      }
      var floor = _base;
      final window = maxPasses - 1;
      if (window == 0) {
        floor = _end;
      } else {
        if (_retainedEnds.length == window) {
          floor = _retainedEnds.removeAt(0);
        }
        _retainedEnds.add(_end);
      }
      final drop = floor - _base;
      if (drop > 0) {
        _events.removeRange(0, drop);
        _base = floor;
      }
      return 0;
    }
    final maxPasses = retainedUpdates;
    var floor = _base;
    if (maxPasses != null) {
      // Events recorded [maxPasses - 1] passes ago have now been observable
      // for maxPasses frame windows; expire them. With maxPasses == 1 that is
      // everything sent before this pass.
      final window = maxPasses - 1;
      if (window == 0) {
        floor = _end;
      } else {
        if (_retainedEnds.length == window) {
          floor = _retainedEnds.removeAt(0);
        }
        _retainedEnds.add(_end);
      }
    }
    var minCursor = _end;
    var maxSkipped = 0;
    for (final reader in _readers) {
      // A reader that lagged past the retention window misses the expired
      // events; its cursor jumps forward so the prefix can be reclaimed.
      final lag = floor - reader._cursor;
      if (lag > 0) {
        reader._cursor = floor;
        if (lag > maxSkipped) maxSkipped = lag;
      }
      if (reader._cursor < minCursor) minCursor = reader._cursor;
    }
    final drop = minCursor - _base;
    if (drop > 0) {
      _events.removeRange(0, drop);
      _base += drop;
    }
    _readerLagged = maxSkipped > 0;
    return maxSkipped;
  }
}

/// A cursor-based reader over an [EventChannel].
///
/// Each call to [drain] returns the events sent since the previous call and
/// advances this reader's cursor to the channel's current end.
final class EventReader<T> {
  final EventChannel<T> _channel;
  int _cursor = 0;

  EventReader._(this._channel);

  /// Whether unread events are available for this reader.
  bool get hasUnread => _cursor < _channel._end;

  /// Invokes [callback] for every unread event without allocating a result
  /// list, then advances this reader's cursor.
  ///
  /// If [callback] throws, the cursor is left unchanged so the unread events can
  /// be retried.
  void forEach(void Function(T event) callback) {
    final from = _cursor - _channel._base;
    final start = from < 0 ? 0 : from;
    final end = _channel._events.length;
    for (var i = start; i < end; i++) {
      callback(_channel._events[i]);
    }
    _cursor = _channel._end;
  }

  /// Consumes every unread event, returning whether there were any.
  ///
  /// Allocates nothing and ignores payloads — use for *signal* events, where a
  /// system only needs to know that something happened (a fire button released,
  /// a restart requested), not the event data. Advancing the cursor here is what
  /// gives once-per-occurrence semantics across a multi-step fixed loop: the
  /// first step that runs consumes the signal, later steps in the same frame see
  /// nothing.
  bool consume() {
    final had = hasUnread;
    _cursor = _channel._end;
    return had;
  }

  /// Returns and consumes all events this reader has not yet seen.
  ///
  /// Allocates the returned list; prefer [forEach] in per-frame systems.
  List<T> drain() {
    final from = _cursor - _channel._base;
    final start = from < 0 ? 0 : from;
    final result = _channel._events.sublist(start);
    _cursor = _channel._end;
    return result;
  }
}

/// A handle that appends events to an [EventChannel].
final class EventWriter<T> {
  final EventChannel<T> _channel;

  EventWriter._(this._channel);

  /// Sends [event] to all readers of the channel.
  void send(T event) => _channel.send(event);
}
