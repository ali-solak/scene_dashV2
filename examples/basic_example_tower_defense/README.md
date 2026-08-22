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

The feature declares its components, events, schedules, and run conditions in
one place:

`lib/features/towers/towers.dart`

```dart
void installTowers(GameBuilder game) {
  game
    ..registerComponent<Tower>()
    ..registerComponent<TowerBeam>()
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
    )
    ..addSystem(
      Schedules.update,
      animateBeams,
      runIf: hasResource<Scene>(),
    );
}
```

The placement system resolves the tap and changes the world:

`lib/features/towers/systems/systems.dart`

```dart
void placeTowers(World world) {
  final scene = world.resource<Scene>();
  final camera = scene.camera;
  if (camera == null) return;

  for (final request in world.events<PlaceTowerRequested>()) {
    final ray = camera.screenPointToRay(request.position, request.viewSize);
    final ground = scene
        .raycast(ray, where: (node) => node.name == groundNodeName)
        ?.worldPoint;
    if (ground != null) placeTowerAt(world, ground.x, ground.z);
  }
}
```

The Flutter shell only emits the request:

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

The HUD reads the world reactively:

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
