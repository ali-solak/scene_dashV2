# Basic tower defense

A small isometric tower defense that shows how Scene-Dash keeps gameplay in
features, while Flutter widgets read the same world.

```text
lib/
  main.dart
  features/
    arena/  creeps/  damage/  towers/  waves/  rules/
      <feature>.dart   installs it
      data/            components, config, bundles
      systems/         plain functions over the world
  hud/
```

`lib/main.dart`

```dart
final game = await SceneGame.boot(
  features: [
    installArena,
    installDamage,
    installCreeps,
    installWaves,
    installTowers,
    installRules,
  ],
);
runApp(GameHost(game: game, child: TowerDefenseApp(game)));
```

A feature declares its components, events, schedules, and run conditions in
one place:

`lib/features/towers/towers.dart`

```dart
void installTowers(GameBuilder game) {
  game
    ..configureEvent<PlaceTowerRequested>()
    ..addSystem(
      Schedules.fixedUpdate,
      placeTowers,
      runIf: hasEvents<PlaceTowerRequested>().and(hasResource<Scene>()),
    )
    ..addSystem(
      Schedules.fixedUpdate,
      fireGuns,
      runIf: inState(GameStatus.playing),
    );
}
```

A kind of tower is a set of components. Systems pick up whatever matches:

`lib/features/towers/data/bundles.dart`

```dart
List<Object> towerBundle(World world, TowerKind kind, Vector3 at) => [
  Tower(kind),
  Health(kind.health),
  SceneTransform.fromVector(at),
  ...switch (kind) {
    TowerKind.bolt => [Gun()],
    TowerKind.pulse => [Pulser()],
    TowerKind.shield => [const ShieldEmitter()],
  },
];
```

Towers and creeps never touch each other's health. They send an event, and
the damage feature resolves it the same way for both:

```dart
world.emit(DamageDealt(victim, boltDamage));
```

The Flutter side only sends the request:

`lib/main.dart`

```dart
Listener(
  onPointerDown: (event) => GameScope.of(context).emit(
    PlaceTowerRequested(event.localPosition, viewSize),
  ),
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

Every rule runs headless, without a GPU:

```sh
flutter run --enable-flutter-gpu
flutter test
```
