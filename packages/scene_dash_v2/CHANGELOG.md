# Changelog
## 0.6.0
- `SceneTransform` sync writes a node only when its transform or bound node
  changed (or the node's matrix was replaced); unchanged entities cost about
  half as much per frame.
- Scene mounting tracks `NodeRef` row changes instead of rescanning every
  bound entity. A node shared by several entities stays mounted until the
  last one drops it, and every entity whose node is mounted is `Mounted`.
- `EntityBuilder.matching` takes `where: (q) => q.having<T>()` instead of
  `require:`/`exclude:` `Type` lists.
- `Game.emit` routes like `world.emit`.
- Requires scene_dash_v2_core 0.6.0.

## 0.5.6
- upgrade to flutter scene 0.24

## 0.5.5
- breaking: removed `equals` from `EntityBuilder`, `WorldBuilder`, and
  `WorldBuilder.pulse`. `select` now compares lists, sets, maps, and iterables
  by contents, one level deep, against a kept copy, so returning a live list
  works without copying it.
- `WorldBuilder.pulse` passes that kept copy to `trigger` as `previous`, so
  in-place changes are visible to it.
- `EntityBuilder.matching` keeps its entity while it matches and skips rescans
  until a watched store changes. Per-frame cost no longer grows with world size.
- Split the combat sample's skill bar into one builder per slot.
- Requires scene_dash_v2_core 0.5.4.

## 0.5.4
- Fix transform sync leaving a node's authored decomposition stale, so a
  later `node.rotation`/`node.scale` write snapped it back.
- Fix headless games booted with `physics:` never running fixed schedules.
- Ignore `onTick` after `shutdown` instead of throwing every frame.
- Remove the unused `Game.dispatch`. use `world.sendEvent` or `world.emit`.

## 0.5.3
- Dispose widget event readers on unmount instead of retaining a reader pool.
- Complete scene-driver and frame-notifier cleanup when app shutdown fails.
- Send unclaimed-component diagnostics to the default debug diagnostic sink.
- Update node-binding documentation and compile representative examples in CI.
- Remove the inspector widgets, inspector snapshot API, package references, documentation,
  and example overlay controls.
- Add `equals:` to both `EntityBuilder` forms and document snapshot selections.
- Prevent event callback failures from replaying UI effects; report failures
  through Flutter and continue delivering the batch.
- Reject negative polling intervals and non-finite or non-positive pulse
  durations, including when widgets update in release builds.
- Refresh entity and world selections when widgets update, including during
  polling intervals.
- Reset pulse feedback on game and builder mode changes while preserving active
  feedback across parent rebuilds.
- Restart polling when the game or interval change.

## 0.5.2
- A variety of ordering fixes for events and command buffers.

## 0.5.1
- breaking: removed debugDraw since flutterscene now provides DebugDraw itself.
- upgrade to flutter_scene 0.23
- updated examples

## 0.5.0
- upgrade to flutter scene 0.22.1 and introduces a way to use authored components for .fscene in ecs via installSceneBaker

## 0.4.0
- upgrade deps

## 0.3.0
- adds gameTween, vector3Tween, colorTween, smoothTo and moveToward

## 0.2.0
- adds new routine mechanism for better organizing sequenced game logic

## 0.1.3
- adds custom schedules feature

## 0.1.2

- minor fixes for pub dev

## 0.1.0

First release.
