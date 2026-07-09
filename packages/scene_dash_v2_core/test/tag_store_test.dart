import 'package:scene_dash_v2_core/advanced.dart';
import 'package:test/test.dart';

void main() {
  group('TagStore', () {
    test('adds membership idempotently', () {
      final store = TagStore();
      store.add(7);
      final revision = store.revision;
      store.add(7);
      expect(store.length, 1);
      expect(store.containsIndex(7), isTrue);
      expect(store.revision, revision);
    });

    test('removes membership via swap removal', () {
      final store = TagStore();
      store.add(1);
      store.add(2);
      store.removeEntityIndex(1);
      expect(store.containsIndex(1), isFalse);
      expect(store.containsIndex(2), isTrue);
      expect(store.length, 1);
    });

    test('insertDynamic ignores the value', () {
      final store = TagStore();
      store.insertDynamic(3, 'whatever');
      expect(store.containsIndex(3), isTrue);
    });

    test('revision tracks membership changes only', () {
      final store = TagStore();
      expect(store.revision, 0);

      store.add(1);
      expect(store.revision, 1);

      store.add(1);
      expect(store.revision, 1);

      store.removeEntityIndex(1);
      expect(store.revision, 2);

      store.removeEntityIndex(1);
      expect(store.revision, 2);
    });
  });
}
