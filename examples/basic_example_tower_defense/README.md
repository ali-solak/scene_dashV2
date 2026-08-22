# Basic tower defense

A minimal game showing how Scene-Dash keeps gameplay in features and reads the same world from Flutter widgets.

```text
lib/
  main.dart
  features/
    towers/
      towers.dart
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

`lib/features/towers/towers.dart`

```dart
void installTowers(GameBuilder game) {
  game
    ..configureEvent<PlaceTowerRequested>()
    ..addSystem(
      Schedules.fixedUpdate,
      placeTowers,
      runIf: hasEvents<PlaceTowerRequested>(),
    );
}
```

`lib/features/towers/systems/systems.dart`

```dart
void placeTowers(World world) {
  final gold = world.resource<Gold>();
  for (final request in world.events<PlaceTowerRequested>()) {
    if (gold.value < towerCost) continue;
    gold.value -= towerCost;
    world.spawn(towerBundle(Vector3(request.x, towerRadius, request.z)));
  }
}
```

`lib/hud/stats.dart`

```dart
GestureDetector(
  onTap: () => GameScope.of(context).emit(
    const PlaceTowerRequested(0, -2),
  ),
  child: WorldBuilder<int>(
    select: (world) => world.resource<Gold>().value,
    builder: (context, gold) => Text('$gold gold'),
  ),
)
```

```sh
flutter run --enable-flutter-gpu
```
