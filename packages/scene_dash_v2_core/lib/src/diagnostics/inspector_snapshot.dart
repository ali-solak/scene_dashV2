/// Debug data collected from a world.
library;

import '../entity/entity.dart';
import '../storage/object_store.dart';
import '../world/world.dart';
import 'name.dart';
import 'system_profiler.dart';

/// A summary of one world.
final class InspectorSnapshot {
  const InspectorSnapshot({
    required this.entityCount,
    required this.stores,
    required this.entities,
    required this.resources,
    required this.systems,
    required this.events,
  });

  /// Live entities at collection time.
  final int entityCount;

  /// Per-store dense counts, in store-registration order.
  final List<StoreSnapshot> stores;

  /// One summary per live entity.
  final List<EntitySnapshot> entities;

  /// Registered resources, in insertion order.
  final List<ResourceSnapshot> resources;

  /// Collected system timings.
  final List<SystemSnapshot> systems;

  /// Registered event channels, in registration order.
  final List<EventChannelSnapshot> events;
}

/// A component or tag store: its type name and dense row count.
final class StoreSnapshot {
  const StoreSnapshot({required this.type, required this.count});

  final String type;
  final int count;
}

/// A live entity summary.
final class EntitySnapshot {
  const EntitySnapshot({
    required this.index,
    required this.generation,
    required this.name,
    required this.componentTypes,
  });

  final int index;
  final int generation;
  final String? name;
  final List<String> componentTypes;
}

/// One resource: its type name and, when the instance overrides
/// `Object.toString` (same default-`Instance of` filter as
/// `debugDescribe`), that rendering.
final class ResourceSnapshot {
  const ResourceSnapshot({required this.type, required this.value});

  final String type;
  final String? value;
}

/// Timing for one system and schedule.
final class SystemSnapshot {
  const SystemSnapshot({
    required this.label,
    required this.schedule,
    required this.lastMs,
    required this.averageMs,
  });

  final String label;
  final String schedule;
  final double lastMs;
  final double averageMs;
}

/// One event channel: its event type name, buffered-event count, and
/// whether the most recent maintenance pass found a lagging reader.
final class EventChannelSnapshot {
  const EventChannelSnapshot({
    required this.type,
    required this.pending,
    required this.readerLagged,
  });

  final String type;
  final int pending;
  final bool readerLagged;
}

/// Component details for one entity.
final class EntityDetailSnapshot {
  const EntityDetailSnapshot({
    required this.index,
    required this.generation,
    required this.name,
    required this.lines,
    required this.stale,
  });

  final int index;
  final int generation;
  final String? name;

  /// One entry per component, in store-registration order.
  final List<String> lines;

  /// Whether the entity is no longer live.
  final bool stale;
}

/// Collects [InspectorSnapshot] data on demand.
final class SnapshotCollector {
  SnapshotCollector(this.world);

  final World world;

  /// Collects the summary snapshot: counts, entity summaries (type names
  /// only), resources, profiled timings, event channels.
  InspectorSnapshot collect() {
    final stores = <StoreSnapshot>[];
    for (final (type, store) in world.stores.entries) {
      stores.add(StoreSnapshot(type: '$type', count: store.length));
    }

    final entities = <EntitySnapshot>[];
    final registry = world.entities;
    for (var index = 0; index < registry.slotCount; index++) {
      if (!registry.isIndexAlive(index)) continue;
      final entity = registry.resolve(index);
      final componentTypes = <String>[];
      for (final (type, store) in world.stores.entries) {
        if (store.containsIndex(index)) componentTypes.add('$type');
      }
      entities.add(
        EntitySnapshot(
          index: entity.index,
          generation: entity.generation,
          name: world.tryGet<Name>(entity)?.value,
          componentTypes: componentTypes,
        ),
      );
    }

    final resources = <ResourceSnapshot>[];
    for (final (type, value) in world.resources.entries) {
      resources.add(
        ResourceSnapshot(type: '$type', value: _overriddenToString(value)),
      );
    }

    final systems = <SystemSnapshot>[];
    final profiler = world.resources.tryGet<SystemProfiler>();
    if (profiler != null) {
      for (final timing in profiler.timings) {
        systems.add(
          SystemSnapshot(
            label: timing.debugName,
            schedule: timing.schedule.id.toString(),
            lastMs: timing.latestMicros / 1000,
            averageMs: timing.average.inMicroseconds / 1000,
          ),
        );
      }
    }

    final events = <EventChannelSnapshot>[];
    for (final (type, channel) in world.debugEventChannels) {
      events.add(
        EventChannelSnapshot(
          type: '$type',
          pending: channel.pendingCount,
          readerLagged: channel.readerLagged,
        ),
      );
    }

    return InspectorSnapshot(
      entityCount: registry.aliveCount,
      stores: stores,
      entities: entities,
      resources: resources,
      systems: systems,
      events: events,
    );
  }

  /// Collects details for one entity.
  EntityDetailSnapshot describeEntity(int index, int generation) {
    final entity = Entity(index, generation);
    if (!world.isAlive(entity)) {
      return EntityDetailSnapshot(
        index: index,
        generation: generation,
        name: null,
        lines: const <String>[],
        stale: true,
      );
    }
    // Use the value text when available.
    final lines = <String>[];
    for (final (type, store) in world.stores.entries) {
      if (!store.containsIndex(index)) continue;
      final value = store is ObjectComponentStore
          ? _overriddenToString(store.valueOf(index))
          : null;
      lines.add(value ?? '$type');
    }
    return EntityDetailSnapshot(
      index: index,
      generation: generation,
      name: world.tryGet<Name>(entity)?.value,
      lines: lines,
      stale: false,
    );
  }

  /// Returns custom text for [value].
  static String? _overriddenToString(Object? value) {
    final text = value?.toString();
    if (text == null || text.startsWith("Instance of '")) return null;
    return text;
  }
}
