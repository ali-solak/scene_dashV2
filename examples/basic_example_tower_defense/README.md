# Basic tower defense

A minimal game showing how Scene-Dash keeps gameplay in features and reads the same world from Flutter widgets.

```text
lib/
  main.dart
  features/
    creeps/
      creeps.dart
      data/
      systems/
  hud/
```

`lib/main.dart`

```dart
final game = await SceneGame.boot(
  features: [installArena, installCreeps, installTowers, installRules],
);
runApp(GameHost(game: game, child: TowerDefenseApp(game)));
```

`lib/features/creeps/creeps.dart`

```dart
void installCreeps(GameBuilder game) {
  game.addSystem(
    Schedules.fixedUpdate,
    walkPath,
    runIf: inState(GameStatus.playing),
  );
}
```

`lib/features/creeps/systems/systems.dart`

```dart
void walkPath(World world) {
  world.query2<SceneTransform, PathProgress>(
    require: const [Creep],
  ).each((entity, at, progress) {
    final target = towerPath[progress.next];
    final step = creepSpeed * world.dt;
    at.x = moveToward(at.x, target.x, step);
    at.z = moveToward(at.z, target.z, step);
  });
}
```

`lib/hud/stats.dart`

```dart
WorldBuilder<int>(
  select: (world) => world.query<Health>(require: const [Creep]).count(),
  builder: (context, alive) => Text('$alive creeps'),
)
```

```sh
flutter run --enable-flutter-gpu
```
