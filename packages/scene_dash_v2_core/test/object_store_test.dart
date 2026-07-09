import 'package:scene_dash_v2_core/advanced.dart';
import 'package:test/test.dart';

final class Name {
  final String value;
  const Name(this.value);
}

void main() {
  group('ObjectComponentStore', () {
    test('inserts and reads back a value', () {
      final store = ObjectComponentStore<Name>();
      store.insert(5, const Name('hero'));
      expect(store.containsIndex(5), isTrue);
      expect(store.valueOf(5)?.value, 'hero');
      expect(store.length, 1);
    });

    test('replacing keeps a single dense row', () {
      final store = ObjectComponentStore<Name>();
      store.insert(2, const Name('a'));
      final afterInsert = store.revision;
      store.insert(2, const Name('b'));
      expect(store.length, 1);
      expect(store.valueOf(2)?.value, 'b');
      expect(store.revision, afterInsert + 1);
    });

    test('swap removal keeps remaining entities addressable', () {
      final store = ObjectComponentStore<Name>();
      store.insert(1, const Name('one'));
      store.insert(2, const Name('two'));
      store.insert(3, const Name('three'));

      store.removeEntityIndex(1); // entity 3 swaps into the hole
      expect(store.length, 2);
      expect(store.containsIndex(1), isFalse);
      expect(store.valueOf(2)?.value, 'two');
      expect(store.valueOf(3)?.value, 'three');
    });

    test('missing entity returns null / -1', () {
      final store = ObjectComponentStore<Name>();
      expect(store.valueOf(99), isNull);
      expect(store.denseIndexOf(99), -1);
      expect(store.containsIndex(99), isFalse);
    });

    test('grows dense and sparse capacity', () {
      final store = ObjectComponentStore<Name>(
        denseCapacity: 2,
        sparseCapacity: 2,
      );
      for (var i = 0; i < 200; i++) {
        store.insert(i, Name('n$i'));
      }
      expect(store.length, 200);
      for (var i = 0; i < 200; i++) {
        expect(store.valueOf(i)?.value, 'n$i');
      }
    });

    test('removing a non-present entity is a no-op', () {
      final store = ObjectComponentStore<Name>();
      store.insert(1, const Name('one'));
      final revision = store.revision;
      store.removeEntityIndex(42);
      expect(store.length, 1);
      expect(store.revision, revision);
    });

    test('revision tracks inserts, replacements, and removals', () {
      final store = ObjectComponentStore<Name>();
      expect(store.revision, 0);

      store.insert(1, const Name('one'));
      expect(store.revision, 1);

      store.insert(1, const Name('uno'));
      expect(store.revision, 2);

      store.removeEntityIndex(1);
      expect(store.revision, 3);
    });
  });
}
