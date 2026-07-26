import '../entity/entity.dart';
import '../storage/object_store.dart';
import '../world/world.dart';
import 'name.dart';

/// One-line entity descriptions for logs and assertion messages.
extension WorldDebugDescribe on World {
  /// Describes [entity] and its components.
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
      final value = store is ObjectComponentStore ? store.valueOf(index) : null;
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
