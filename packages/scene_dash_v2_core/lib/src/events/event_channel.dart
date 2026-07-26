/// Untyped event channel controls.
abstract interface class EventChannelMaintenance {
  /// Reclaims consumed events; see [EventChannel.update].
  ///
  /// Returns the largest number of unread events any single reader lost to
  /// the retention window this pass (`0` when no reader fell behind).
  int update();

  /// Number of buffered events.
  int get pendingCount;

  /// Whether a reader lost events during the last [update].
  bool get readerLagged;

  /// Adds [event] using its runtime type.
  void sendDynamic(Object event);

  /// Discards every buffered event; see [EventChannel.clear].
  void clear();
}

/// A buffered event channel with independent readers.
///
/// Unread events remain for [retainedUpdates] updates.
/// Use `null` to keep them until every reader consumes them.
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

  /// Whether the channel contains events.
  bool get isNotEmpty => _events.isNotEmpty;

  /// Whether the channel buffers no events. See [isNotEmpty].
  bool get isEmpty => _events.isEmpty;

  /// Whether the channel has readers.
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

  /// Creates a reader at the oldest buffered event.
  EventReader<T> readerFromStart() {
    final reader = EventReader<T>._(this).._cursor = _base;
    _readers.add(reader);
    return reader;
  }

  /// Creates a writer bound to this channel.
  EventWriter<T> writer() => EventWriter<T>._(this);

  /// Discards every buffered event.
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

  /// Removes consumed and expired events.
  ///
  /// Returns the largest number of events missed by one reader.
  @override
  int update() {
    _readerLagged = false;
    if (_readers.isEmpty) {
      // Apply retention before the first reader exists.
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
      // Advance readers past expired events.
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

  /// Consumes unread events and reports whether any existed.
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
