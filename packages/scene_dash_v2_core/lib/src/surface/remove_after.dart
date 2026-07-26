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
  Int32List _generations = Int32List(8);
  Float64List _deadlines = Float64List(8);
  List<Type?> _types = List<Type?>.filled(8, null, growable: false);
  int _length = 0;

  RemoveAfterTracker._(this.world);

  /// The world's tracker, created on first use.
  static RemoveAfterTracker of(World world) => world.resources
      .getOrInsert<RemoveAfterTracker>(() => RemoveAfterTracker._(world));

  /// Number of tracked deadlines.
  int get length => _length;

  /// Removes [type] from [entity] after [seconds].
  void track(Entity entity, Type type, double seconds) {
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
      // Swap-remove first; the row swapped in from the end has not been
      // ticked yet this pass, so continuing at [i] ticks it next.
      _removeRow(i);
      final entity = world.entities.resolve(index);
      if (entity.generation != generation) continue;
      if (!world.stores.isRegistered(type) ||
          !world.stores.require(type).containsIndex(index)) {
        continue;
      }
      world.commands.removeByType(type, entity);
    }
  }

  /// `World.reset` interplay: every tracked entity died, so drop all rows.
  void reset() => _length = 0;

  int _rowOf(Entity entity, Type type) {
    for (var i = 0; i < _length; i++) {
      if (_indices[i] == entity.index &&
          _generations[i] == entity.generation &&
          _types[i] == type) {
        return i;
      }
    }
    return -1;
  }

  void _removeRow(int row) {
    final last = _length - 1;
    if (row != last) {
      _indices[row] = _indices[last];
      _generations[row] = _generations[last];
      _deadlines[row] = _deadlines[last];
      _types[row] = _types[last];
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
    _generations = Int32List(newCap)..setRange(0, _length, _generations);
    _deadlines = Float64List(newCap)..setRange(0, _length, _deadlines);
    final types = List<Type?>.filled(newCap, null, growable: false);
    for (var i = 0; i < _length; i++) {
      types[i] = _types[i];
    }
    _types = types;
  }
}
