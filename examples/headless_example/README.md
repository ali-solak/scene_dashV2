# Headless example

The ECS core running without Flutter. It is a tiny "race": one player moves
down a track, a short-lived boost marker runs out, and a referee records
the winner at the finish line. Pure Dart, no scene, no GPU.

What it shows:

- a feature installing systems on `startup` and `fixedUpdate` with
  `reads:`/`writes:`, `after:` ordering and an `every(...)` run condition;
- tags (`registerTag`) and record queries with `require:` and `.each`;
- events (`world.emit`/`world.events<T>()`) between systems;
- timed despawn with `DespawnAfter`;
- `TestGame.headless` running the same frame pipeline as a device, in
  plain `dart test`, including the determinism check (identical spawns +
  identical inputs ⇒ identical runs).

Run it:

```bash
flutter pub get          # from the repo root (pub workspace)
cd examples/headless_example
dart test
```

Start with [`lib/game.dart`](lib/game.dart) (the whole game: components,
systems, `installRace`) and [`test/game_test.dart`](test/game_test.dart)
(the frame-exact assertions).
