/// The inspector's snapshot boundary (I1): plain-data views of a world,
/// collected on demand by [SnapshotCollector].
///
/// Every field is a string, int, bool or a list of those — serializable by
/// construction, so a frontend (the in-app overlay today, a DevTools web
/// page later) can consume the same data without holding live object
/// references. Wave 1 is read-only: nothing here mutates the world.
library;

import '../entity/entity.dart';
import '../storage/object_store.dart';
import '../world/world.dart';
import 'name.dart';
import 'system_profiler.dart';

/// One collected view of a world: counts, entity summaries, resources,
/// system timings and event channels. Plain data — see the library docs.
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

  /// One summary per live entity — type names only; the per-component
  /// `toString` values are collected lazily by
  /// [SnapshotCollector.describeEntity], on selection.
  final List<EntitySnapshot> entities;

  /// Registered resources, in insertion order.
  final List<ResourceSnapshot> resources;

  /// Profiled (system, schedule) timings — empty unless the app was built
  /// with `AppDiagnostics(profileSystems: true)`.
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

/// One live entity: handle parts, its `Name` when present, and component
/// *type names* only (summaries stay cheap — values are detail-tier).
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

/// One profiled (system, schedule) pair: the D11 identity-derived label
/// (honoring a `label:` override), the schedule id, and the last and
/// rolling-average run cost in milliseconds.
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

/// The detail view for one selected entity: the `debugDescribe` values
/// (M6 — a component's own `toString` when overridden, its type name
/// otherwise), one line per component. Collected only on selection.
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

  /// True when the handle no longer resolves (despawned since the summary
  /// was collected) — [lines] is empty then.
  final bool stale;
}

/// Collects [InspectorSnapshot]s from a world, on demand (I3): a frontend
/// polls it on its own timer — the collector itself runs nothing per
/// frame and costs nothing while no frontend asks. Collection allocates
/// (bounded by world size); this is debug tooling, not a hot path.
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

  /// Collects the detail view for the entity at ([index], [generation]) —
  /// the `debugDescribe` component values. Called only when a frontend
  /// selects the entity, never during [collect] (detail stays lazy).
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
    // One line per component, by `debugDescribe`'s M6 rule: the value's
    // own `toString` when overridden, the type name otherwise.
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

  /// [value]'s `toString` when it overrides `Object.toString`, else null —
  /// the same default-`Instance of '...'` detection `debugDescribe` uses.
  static String? _overriddenToString(Object? value) {
    final text = value?.toString();
    if (text == null || text.startsWith("Instance of '")) return null;
    return text;
  }
}
