/// Keeps recent input actions in order.
///
/// Entries use wall time and expire after [window].
final class InputBuffer<T> {
  /// Seconds a recorded action stays consumable. Inclusive: an entry exactly
  /// [window] old is still live; it expires strictly after.
  final double window;

  /// Maximum simultaneously buffered entries; recording into a full buffer
  /// drops the oldest (the newest press wins under spam).
  final int capacity;

  /// Whether the frame drivers age this buffer each frame (the default).
  /// `false` hands the clock to the game: tick [advance] yourself.
  final bool autoAdvance;

  final List<T?> _actions;
  final List<double> _stamps;
  int _head = 0; // Index of the oldest entry.
  int _length = 0;
  double _now = 0;

  InputBuffer({this.window = 0.15, this.capacity = 8, this.autoAdvance = true})
    : assert(capacity > 0, 'InputBuffer needs a positive capacity.'),
      _actions = List<T?>.filled(capacity, null),
      _stamps = List<double>.filled(capacity, 0);

  /// Advances the buffer's internal clock by [unscaledDt] seconds. The
  /// frame drivers call this for every [autoAdvance] buffer; only a
  /// buffer constructed with `autoAdvance: false` ticks it by hand.
  void advance(double unscaledDt) => _now += unscaledDt;

  /// Records a press of [action], stamped at the current clock. When the
  /// buffer is full, the oldest entry is dropped.
  void record(T action) {
    if (_length == capacity) {
      // Full: overwrite the oldest slot and move the head past it.
      _head = (_head + 1) % capacity;
      _length -= 1;
    }
    final slot = (_head + _length) % capacity;
    _actions[slot] = action;
    _stamps[slot] = _now;
    _length += 1;
  }

  bool _expired(int slot) => _now - _stamps[slot] > window;

  /// Removes [slot] (an occupied ring slot) from the ring, preserving the
  /// order of the entries after it.
  void _removeAt(int slot) {
    // Shift everything after `slot` back by one; at most `capacity - 1` moves.
    var i = slot;
    var next = (i + 1) % capacity;
    final tail = (_head + _length) % capacity;
    while (next != tail) {
      _actions[i] = _actions[next];
      _stamps[i] = _stamps[next];
      i = next;
      next = (i + 1) % capacity;
    }
    _actions[i] = null;
    _length -= 1;
  }

  /// Drops expired entries from the front.
  void _pruneFront() {
    while (_length > 0 && _expired(_head)) {
      _actions[_head] = null;
      _head = (_head + 1) % capacity;
      _length -= 1;
    }
  }

  /// Removes and reports the **oldest** unexpired [action], leaving other
  /// actions in place. Oldest-first is the souls convention: the earliest
  /// intent wins. Returns `false` when no live entry matches.
  bool consume(T action) {
    _pruneFront();
    for (var n = 0; n < _length; n++) {
      final slot = (_head + n) % capacity;
      if (_actions[slot] == action) {
        _removeAt(slot);
        return true;
      }
    }
    return false;
  }

  /// Removes the oldest entry found in [actions].
  T? consumeAny(Set<T> actions) {
    _pruneFront();
    for (var n = 0; n < _length; n++) {
      final slot = (_head + n) % capacity;
      final candidate = _actions[slot] as T;
      if (actions.contains(candidate)) {
        _removeAt(slot);
        return candidate;
      }
    }
    return null;
  }

  /// Whether an unexpired [action] is buffered, without removing it.
  bool has(T action) {
    _pruneFront();
    for (var n = 0; n < _length; n++) {
      if (_actions[(_head + n) % capacity] == action) return true;
    }
    return false;
  }

  /// Discards every buffered entry. Call on hard state interrupts (stagger,
  /// death) so stale intents do not fire out of a hit.
  void clear() {
    for (var n = 0; n < _length; n++) {
      _actions[(_head + n) % capacity] = null;
    }
    _head = 0;
    _length = 0;
  }
}

/// Advances every automatic input buffer.
void advanceInputBuffers(Iterable<Object> resources, double unscaledDt) {
  for (final resource in resources) {
    if (resource is InputBuffer && resource.autoAdvance) {
      resource.advance(unscaledDt);
    }
  }
}
