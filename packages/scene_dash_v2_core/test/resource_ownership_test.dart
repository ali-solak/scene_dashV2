import 'package:scene_dash_v2_core/advanced.dart';
import 'package:test/test.dart';

final class Config {
  final int value;
  const Config(this.value);
}

void main() {
  test('insertResource rejects a duplicate of the same type', () {
    final app = App()..insertResource<Config>(const Config(1));
    expect(
      () => app.insertResource<Config>(const Config(2)),
      throwsA(isA<StateError>()),
    );
    // The first instance is still the one in the world.
    expect(app.world.resources.get<Config>().value, 1);
  });

  test('replaceResource swaps the instance intentionally', () {
    final app = App()
      ..insertResource<Config>(const Config(1))
      ..replaceResource<Config>(const Config(2));
    expect(app.world.resources.get<Config>().value, 2);
  });

  test('replaceResource also works when nothing is present yet', () {
    final app = App()..replaceResource<Config>(const Config(7));
    expect(app.world.resources.get<Config>().value, 7);
  });
}
