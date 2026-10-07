import 'dart:typed_data';

final class StoreMembership {
  final List<Uint32List> _columns = <Uint32List>[];

  int get wordCount => _columns.length;

  void add(int entityIndex, int storeId) {
    final word = storeId >> 5;
    while (_columns.length <= word) {
      _columns.add(Uint32List(16));
    }
    var column = _columns[word];
    if (entityIndex >= column.length) {
      var capacity = column.length;
      while (capacity <= entityIndex) {
        capacity *= 2;
      }
      column = _columns[word] = Uint32List(capacity)
        ..setRange(0, column.length, column);
    }
    column[entityIndex] |= 1 << (storeId & 31);
  }

  void remove(int entityIndex, int storeId) {
    final word = storeId >> 5;
    if (word >= _columns.length) return;
    final column = _columns[word];
    if (entityIndex < column.length) {
      column[entityIndex] &= ~(1 << (storeId & 31));
    }
  }

  int bitsAt(int word, int entityIndex) {
    final column = _columns[word];
    return entityIndex < column.length ? column[entityIndex] : 0;
  }
}
