# Headless example

The ECS core running without Flutter: a tiny "race" where a player and two
boosted runners move down a track, a referee watches the finish line, and
a run-state machine reports the result. Pure Dart, no scene, no GPU.

What it demonstrates:

- a feature installing systems across schedules (`startup`, fixed update,
  `update`) with `reads:`/`writes:` declarations;
- record queries with `require:`/`exclude:` and the `.each` idiom;
- events (`world.emit`/`world.events<T>()`) between systems;
- a state machine (`addState`, `OnEnter`, `inState`) and run-scoped
  entities (`DespawnOnExit`);
- `TestGame.headless` driving the exact device frame pipeline in plain
  `dart test`, including the determinism check (identical spawns +
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
