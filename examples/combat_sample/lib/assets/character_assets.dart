library;

import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_scene/scene.dart';

/// Rig files this slice actually uses (general/hits/deaths, locomotion,
/// dodges/strafes, melee).
const List<String> _rigFiles = [
  'assets/animation/Rig_Medium_General.glb',
  'assets/animation/Rig_Medium_MovementBasic.glb',
  'assets/animation/Rig_Medium_MovementAdvanced.glb',
  'assets/animation/Rig_Medium_CombatMelee.glb',
  'assets/animation/Rig_Medium_Special.glb',
];

const String _barbarianScene = 'assets/characters/Barbarian.glb';

class CharacterAssets {
  CharacterAssets({
    required this.knight,
    required this.barbarians,
    required this.clips,
    this.sword,
    this.axe,
    this.shield,
  });

  final Node knight;

  final List<Node> barbarians;

  late final List<bool> _lent = List<bool>.filled(
    barbarians.length,
    false,
    growable: true,
  );

  void addBarbarian(Node node) {
    barbarians.add(node);
    _lent.add(false);
  }

  /// Lends a free model index, or null when the pool is exhausted (the
  /// caller falls back to a graybox capsule).
  int? takeBarbarian() {
    for (var i = 0; i < _lent.length; i++) {
      if (!_lent[i]) {
        _lent[i] = true;
        return i;
      }
    }
    return null;
  }

  /// Returns a model to the pool.
  void releaseBarbarian(int index) {
    if (index < 0 || index >= _lent.length) return;
    _lent[index] = false;
    barbarians[index].detach();
  }

  final Node? sword;
  final Node? axe;

  final Node? shield;

  final Map<String, Animation> clips;

  Animation clip(String name) {
    final animation = clips[name];
    if (animation == null) {
      throw StateError('rig clip "$name" not found');
    }
    return animation;
  }
}

Future<CharacterAssets> loadCharacterAssets({
  required int barbarianCount,
  ResourceGroup? loading,
}) async {
  final scenes = await SceneRegistry.load();

  // Start independent loads together.
  final knightFuture = _track(
    loading,
    scenes.loadScene('assets/characters/Knight.glb'),
  );
  final barbarianFuture = _track(loading, scenes.loadScene(_barbarianScene));
  final rigFutures = [
    for (final path in _rigFiles) _track(loading, scenes.loadScene(path)),
  ];
  final swordFuture = _track(loading, _loadWeapon('sword_2handed'));
  final axeFuture = _track(loading, _loadWeapon('axe_2handed'));
  final shieldFuture = _track(loading, _loadWeapon('shield_square_color'));

  final knight = await knightFuture;
  // One load, one clone per body: clones carry their own skin data, and
  // share GPU geometry and textures.
  final template = await barbarianFuture;
  final barbarians = [
    for (var i = 0; i < barbarianCount; i++) template.clone(),
  ];

  // Merge clips in rig order.
  final clips = <String, Animation>{};
  for (final rigFuture in rigFutures) {
    for (final animation in (await rigFuture).parsedAnimations) {
      clips[animation.name] = animation;
    }
  }
  return CharacterAssets(
    knight: knight,
    barbarians: barbarians,
    clips: clips,
    // Two handed weapons.
    sword: await swordFuture,
    axe: await axeFuture,
    // Colored shield.
    shield: await shieldFuture,
  );
}

Future<T> _track<T>(ResourceGroup? loading, Future<T> load) =>
    loading?.add(load) ?? load;

Future<Uint8List> _assetBytes(String path) async {
  final data = await rootBundle.load(path);
  return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}

Future<Uint8List> _weaponBytes(String uri) async {
  return _assetBytes('assets/character_assets/$uri');
}

/// Weapons are multi-file glTFs; a failed import (unsupported extension)
/// costs the weapon, never the fight.
Future<Node?> _loadWeapon(String name) async {
  try {
    return await Node.fromGltfBytes(
      await _weaponBytes('$name.gltf'),
      resolveUri: _weaponBytes,
    );
  } on Object catch (error) {
    debugPrint('combat_sample: weapon "$name" unavailable: $error');
    return null;
  }
}
