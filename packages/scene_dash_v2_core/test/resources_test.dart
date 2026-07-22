import 'package:scene_dash_v2_core/advanced.dart';
import 'package:test/test.dart';

final class Config {
  final int seed;
  const Config(this.seed);
}

void main() {
  group('Resources', () {
    test('inserts and reads a resource', () {
      final resources = Resources()..insert(const Config(42));
      expect(resources.get<Config>().seed, 42);
      expect(resources.contains<Config>(), isTrue);
    });

    test('throws when a resource is missing', () {
      final resources = Resources();
      expect(resources.get<Config>, throwsStateError);
      expect(resources.tryGet<Config>(), isNull);
    });

    test('insert replaces the existing instance', () {
      final resources = Resources()
        ..insert(const Config(1))
        ..insert(const Config(2));
      expect(resources.get<Config>().seed, 2);
    });

    test(
      'getOrInsert returns the existing resource without calling orElse',
      () {
        final resources = Resources()..insert(const Config(1));
        var called = false;
        final config = resources.getOrInsert<Config>(() {
          called = true;
          return const Config(2);
        });
        expect(config.seed, 1);
        expect(called, isFalse);
      },
    );

    test('getOrInsert inserts and returns orElse() when absent', () {
      final resources = Resources();
      final config = resources.getOrInsert<Config>(() => const Config(7));
      expect(config.seed, 7);
      expect(resources.contains<Config>(), isTrue);
      // A second call now hits the inserted instance.
      expect(
        resources.getOrInsert<Config>(() => const Config(9)),
        same(config),
      );
    });

    test('remove returns and clears the resource', () {
      final resources = Resources()..insert(const Config(9));
      expect(resources.remove<Config>()?.seed, 9);
      expect(resources.contains<Config>(), isFalse);
    });
  });
}
