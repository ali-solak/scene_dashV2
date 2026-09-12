# Changelog

## 0.5.3
- Dispose widget event readers on unmount instead of retaining a reader pool.
- Complete scene-driver and frame-notifier cleanup when app shutdown fails.
- Send unclaimed-component diagnostics to the default debug diagnostic sink.
- Update node-binding documentation and compile representative examples in CI.
- Remove the inspector widgets, snapshot API, package references, documentation,
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
- Restart polling when the game or interval change

## 0.5.2
- - a variety of ordering fixes for events and command buffers

## 0.5.1
- breaking: removed debugDraw since flutterscene now provides DebugDraw itself.
- upgrade to flutter_scene 0.23
- updated examples

## 0.5.0
- upgrade to flutter scene 0.22.1 and introduces a way to use authored components for .fscene in ecs via installSceneBaker

## 0.4.0
- upgrade deps

## 0.3.0
- adds gameTween, vector3Tween, colorTween, smoothTo adn moveToward

## 0.2.0
- adds new routine mechanism for better organizing sequenced game logic

## 0.1.3
- adds custom schedules feature

## 0.1.2

- minor fixes for pub dev

## 0.1.0

First release.
