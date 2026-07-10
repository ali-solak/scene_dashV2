import '../entity/entity.dart';
import '../storage/object_store.dart';
import '../world/world.dart';
import 'name.dart';

/// One-line entity descriptions for logs and assertion messages.
extension WorldDebugDescribe on World {
  /// Renders [entity] as one line for a log or assert:
  ///
  /// ```text
  /// Entity(3 v2) "Boss" [SceneTransform, Health, Name]
  /// Entity(7 v1) [Position, charging (0.42s)]
  /// Entity(3 v1) <stale>
  /// ```
  ///
  /// The quoted label appears when the entity carries a [Name]. Each
  /// bracket entry is the component's `toString` when it overrides
  /// `Object.toString` — a component carrying a `Machine`, say, describes
  /// its live state — and the type otherwise, detected by the default
  /// `Instance of '...'` shape; entries follow store-registration order,
  /// and dead handles render `<stale>`.
  ///
  /// Debug surface: scans every registered store and allocates the string —
  /// do not call per-frame in release code.
  String debugDescribe(Entity entity) {
    if (!isAlive(entity)) return '$entity <stale>';
    final index = entity.index;
    final buffer = StringBuffer()..write(entity);
    final name = tryGet<Name>(entity);
    if (name != null) buffer.write(' "${name.value}"');
    buffer.write(' [');
    var first = true;
    for (final (type, store) in stores.entries) {
      if (!store.containsIndex(index)) continue;
      if (!first) buffer.write(', ');
      first = false;
      final value =
          store is ObjectComponentStore ? store.valueOf(index) : null;
      final text = value?.toString();
      if (text == null || text.startsWith("Instance of '")) {
        buffer.write(type);
      } else {
        buffer.write(text);
      }
    }
    buffer.write(']');
    return buffer.toString();
  }
}
