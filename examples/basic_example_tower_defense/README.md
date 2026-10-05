# Basic tower defense

A small game that shows how Scene-Dash keeps gameplay in features, while
Flutter widgets read the same world.

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

The feature declares its components, events, schedules, and run conditions in
one place:

`lib/features/towers/towers.dart`

```dart
void installTowers(GameBuilder game) {
  game
    ..registerComponent<Tower>()
    ..configureEvent<PlaceTowerRequested>()
    ..addSystem(
      Schedules.fixedUpdate,
      placeTowers,
      runIf: hasEvents<PlaceTowerRequested>().and(hasResource<Scene>()),
    )
    ..addSystem(
      Schedules.fixedUpdate,
      fireTowers,
      runIf: inState(GameStatus.playing),
    );
}
```

The placement system turns the tap into a ground position and changes the
world:

`lib/features/towers/systems/systems.dart`

```dart
void placeTowers(World world) {
  for (final request in world.events<PlaceTowerRequested>()) {
    final ground = groundFromTap(world, request);
    if (ground != null) placeTowerAt(world, ground);
  }
}
```

`groundFromTap` holds the camera and raycast details. `placeTowerAt` checks
the cost and the spot, then spawns the tower bundle.

The Flutter side only sends the request:

`lib/main.dart`

```dart
GestureDetector(
  onTapDown: (details) {
    final viewSize = context.size;
    if (viewSize == null) return;
    GameScope.of(context).emit(
      PlaceTowerRequested(details.localPosition, viewSize),
    );
  },
  child: child,
)
```

The HUD reads the world and rebuilds when the value changes:

`lib/hud/stats.dart`

```dart
WorldBuilder<int>(
  select: (world) => world.resource<Gold>().value,
  builder: (context, gold) => Text('$gold gold'),
)
```

```sh
flutter run --enable-flutter-gpu
```
