import 'package:scene_dash_v2_core/scene_dash_v2_core.dart';
import 'package:scene_dash_v2_core/advanced.dart' show ComponentStore;
import 'package:scene_dash_v2_benchmarks/harness.dart';

class Health {
  Health(this.current);
  double current;
}

final class Dead implements Tag {
  const Dead();
}

final class CachedMatch<T extends Object> {
  CachedMatch(World world, {required List<Type> exclude})
    : _query = world.query<T>(exclude: exclude),
      _stores = [for (final type in [T, ...exclude]) world.stores.require(type)];

  final QueryView1<T> _query;
  final List<ComponentStore> _stores;
  Entity? _matched;
  int _missRevision = -1;

  T? resolve() {
    final matched = _matched;
    if (matched != null) {
      final component = _query.get(matched);
      if (component != null) return component;
      _matched = null;
    }
    final revision = _revision();
    if (revision == _missRevision) return null;
    final hit = _query.firstOrNull;
    if (hit == null) {
      _missRevision = revision;
      return null;
    }
    _matched = hit.$1;
    _missRevision = -1;
    return hit.$2;
  }

  int _revision() {
    var revision = 0;
    for (final store in _stores) {
      revision += store.revision;
    }
    return revision;
  }
}

TestGame _world({required int dead, required bool aliveLast}) {
  final game = TestGame.headless(
    features: [
      (g) => g
        ..registerComponent<Health>()
        ..registerTag<Dead>(),
    ],
  );
  for (var i = 0; i < dead; i++) {
    game.world.spawn([Health(0), const Dead()]);
  }
  if (aliveLast) game.world.spawn([Health(100)]);
  game.start();
  return game;
}

void main() {
  var sink = 0.0;
  for (final count in [100, 1000, 10000]) {
    for (final aliveLast in [true, false]) {
      final game = _world(dead: count, aliveLast: aliveLast);
      final world = game.world;
      final label = aliveLast ? 'hit, match scanned last' : 'miss';
      benchRepeat('per-frame query; $label; $count dead', 1, () {
        sink +=
            world.query<Health>(exclude: const [Dead]).firstOrNull?.$2.current ??
            0;
      });
      final cached = CachedMatch<Health>(world, exclude: const [Dead]);
      benchRepeat('cached match;    $label; $count dead', 1, () {
        sink += cached.resolve()?.current ?? 0;
      });
    }
  }
  print('sink=$sink');
}
