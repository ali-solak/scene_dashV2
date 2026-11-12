/// Timed component removal.
library;

import 'dart:typed_data';

import '../entity/entity.dart';
import '../world/world.dart';

/// Tracks component removal deadlines.
final class RemoveAfterTracker {
  /// The world whose components this tracker expires.
  final World world;

  Int32List _indices = Int32List(8);
  Uint32List _generations = Uint32List(8);
  Float64List _deadlines = Float64List(8);
  List<Type?> _types = List<Type?>.filled(8, null, growable: false);
  Int32List _next = Int32List(8);
  Int32List _headByIndex = Int32List(0);
  int _length = 0;

  RemoveAfterTracker._(this.world);

  /// The world's tracker, created on first use.
  static RemoveAfterTracker of(World world) => world.resources
      .getOrInsert<RemoveAfterTracker>(() => RemoveAfterTracker._(world));

  /// Number of tracked deadlines.
  int get length => _length;

  /// Removes [type] from [entity] after [seconds].
  void track(Entity entity, Type type, double seconds) {
    if (!world.isAlive(entity)) return;
    final row = _rowOf(entity, type);
    if (row >= 0) {
      _deadlines[row] = seconds;
      return;
    }
    _ensureCapacity(_length + 1);
    _indices[_length] = entity.index;
    _generations[_length] = entity.generation;
    _deadlines[_length] = seconds;
    _types[_length] = type;
    _link(_length, entity.index);
    _length++;
  }

  /// Cancels a removal deadline.
  void cancel(Entity entity, Type type) {
    final row = _rowOf(entity, type);
    if (row >= 0) _removeRow(row);
  }

  /// Seconds remaining until ([entity], [type]) is removed, or `null` when
  /// untracked, canceled, or the entity is no longer alive.
  double? expiryOf(Entity entity, Type type) {
    if (!world.isAlive(entity)) return null;
    final row = _rowOf(entity, type);
    if (row < 0) return null;
    final remaining = _deadlines[row];
    return remaining < 0 ? 0 : remaining;
  }

  /// Advances deadlines and queues expired removals.
  void tick(double dt) {
    var i = 0;
    while (i < _length) {
      final remaining = _deadlines[i] - dt;
      if (remaining > 0) {
        _deadlines[i] = remaining;
        i++;
        continue;
      }
      final index = _indices[i];
      final generation = _generations[i];
      final type = _types[i]!;
      _removeRow(i);
      final entity = world.entities.resolve(index);
      if (entity.generation != generation) continue;
      if (!(world.stores.lookup(type)?.containsIndex(index) ?? false)) {
        continue;
      }
      world.commands.removeByType(type, entity);
    }
  }

  /// `World.reset` interplay: every tracked entity died, so drop all rows.
  void reset() {
    _length = 0;
    _headByIndex.fillRange(0, _headByIndex.length, 0);
  }

  int _rowOf(Entity entity, Type type) {
    final index = entity.index;
    if (index >= _headByIndex.length) return -1;
    final generation = entity.generation;
    var row = _headByIndex[index] - 1;
    while (row >= 0) {
      if (_generations[row] == generation && _types[row] == type) return row;
      row = _next[row] - 1;
    }
    return -1;
  }

  void _link(int row, int index) {
    if (index >= _headByIndex.length) {
      var capacity = _headByIndex.isEmpty ? 64 : _headByIndex.length;
      while (capacity <= index) {
        capacity *= 2;
      }
      _headByIndex = Int32List(capacity)
        ..setRange(0, _headByIndex.length, _headByIndex);
    }
    _next[row] = _headByIndex[index];
    _headByIndex[index] = row + 1;
  }

  void _relink(int index, int from, int to) {
    if (_headByIndex[index] == from + 1) {
      _headByIndex[index] = to;
      return;
    }
    var row = _headByIndex[index] - 1;
    while (_next[row] != from + 1) {
      row = _next[row] - 1;
    }
    _next[row] = to;
  }

  void _removeRow(int row) {
    _relink(_indices[row], row, _next[row]);
    final last = _length - 1;
    if (row != last) {
      _relink(_indices[last], last, row + 1);
      _indices[row] = _indices[last];
      _generations[row] = _generations[last];
      _deadlines[row] = _deadlines[last];
      _types[row] = _types[last];
      _next[row] = _next[last];
    }
    _types[last] = null;
    _length = last;
  }

  void _ensureCapacity(int needed) {
    if (needed <= _indices.length) return;
    var newCap = _indices.length;
    while (newCap < needed) {
      newCap *= 2;
    }
    _indices = Int32List(newCap)..setRange(0, _length, _indices);
    _generations = Uint32List(newCap)..setRange(0, _length, _generations);
    _deadlines = Float64List(newCap)..setRange(0, _length, _deadlines);
    _next = Int32List(newCap)..setRange(0, _length, _next);
    final types = List<Type?>.filled(newCap, null, growable: false);
    for (var i = 0; i < _length; i++) {
      types[i] = _types[i];
    }
    _types = types;
  }
}
