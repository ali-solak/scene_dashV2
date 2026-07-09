import '../entity/entity.dart';
import 'commands.dart';

/// Fluent deferred commands targeting one entity.
final class EntityCommands {
  final Commands _commands;

  /// The entity these commands target.
  final Entity entity;

  EntityCommands(this._commands, this.entity);

  /// Queues inserting [component] of type [T] onto [entity].
  EntityCommands insert<T>(T component) {
    _commands.insert<T>(entity, component);
    return this;
  }

  /// Queues removing the component of type [T] from [entity].
  EntityCommands remove<T>() {
    _commands.remove<T>(entity);
    return this;
  }

  /// Queues despawning [entity].
  void despawn() {
    _commands.despawn(entity);
  }
}
