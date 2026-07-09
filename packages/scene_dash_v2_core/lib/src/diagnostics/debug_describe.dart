import '../entity/entity.dart';
import '../world/world.dart';
import 'name.dart';

/// One-line entity descriptions for logs and assertion messages.
extension WorldDebugDescribe on World {
  /// Renders [entity] as one line for a log or assert:
  ///
  /// ```text
  /// Entity(3 v2) "Boss" [SceneTransform, Health, Name]
  /// Entity(7 v1) [Position, Velocity]
  /// Entity(3 v1) <stale>
  /// ```
  ///
  /// The quoted label appears when the entity carries a [Name]; the bracket
  /// list is `debugComponentsOf` (every registered type the entity carries,
  /// in store-registration order); dead handles render `<stale>`.
  ///
  /// Debug surface: scans every registered store and allocates the string —
  /// do not call per-frame in release code.
  String debugDescribe(Entity entity) {
    if (!isAlive(entity)) return '$entity <stale>';
    final buffer = StringBuffer()..write(entity);
    final name = tryGet<Name>(entity);
    if (name != null) buffer.write(' "${name.value}"');
    buffer
      ..write(' [')
      ..writeAll(debugComponentsOf(entity), ', ')
      ..write(']');
    return buffer.toString();
  }
}
