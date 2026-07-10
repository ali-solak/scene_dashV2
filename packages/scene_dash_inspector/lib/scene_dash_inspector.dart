/// Scene-Dash v2 inspector, wave 1: a read-only overlay for a running
/// game — entities (filter, tap for detail), resources, system timings,
/// event channels.
///
/// Drop [InspectorOverlay] into any `Stack` under a `GameScope`; it polls
/// the core snapshot boundary (`SnapshotCollector`, exported by
/// `scene_dash_v2_core/advanced.dart`) on a timer while visible and costs
/// nothing while hidden. It never reads the world directly and mutates
/// nothing — the same snapshot data will feed the DevTools frontend in
/// wave 2.
library;

export 'src/inspector_overlay.dart' show InspectorOverlay, InspectorPanel;
