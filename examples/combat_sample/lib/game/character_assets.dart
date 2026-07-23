library;

import 'dart:async' show unawaited;
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_scene/scene.dart';

import '../anim/hemisphere.dart';

/// Rig files this slice actually uses (general/hits/deaths, locomotion,
/// dodges/strafes, melee).
const List<String> _rigFiles = [
  'assets/animation/Rig_Medium_General.glb',
  'assets/animation/Rig_Medium_MovementBasic.glb',
  'assets/animation/Rig_Medium_MovementAdvanced.glb',
  'assets/animation/Rig_Medium_CombatMelee.glb',
  'assets/animation/Rig_Medium_Special.glb',
];

const int _openingBarbarians = 2;
const int _barbarianSlots = 10;

String _barbarianScene(int index) => 'assets/characters/Barbarian_$index.glb';

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
  Future<void> Function()? _loadReserve;

  late final List<bool> _lent = List<bool>.filled(
    barbarians.length,
    false,
    growable: true,
  );

  void addBarbarian(Node node) {
    barbarians.add(node);
    _lent.add(false);
  }

  /// Starts the deferred reserve realizations once the first scene frame is
  /// visible. Safe to call more than once.
  void loadReserve() {
    final load = _loadReserve;
    if (load == null) return;
    _loadReserve = null;
    unawaited(load());
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

  /// Returns a model to the pool and unparents it, so the next borrower
  /// can hang it under a fresh wrapper.
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
  if (barbarianCount > _barbarianSlots) {
    throw ArgumentError.value(
      barbarianCount,
      'barbarianCount',
      'the build hook provides $_barbarianSlots independent scene slots',
    );
  }
  final scenes = await SceneRegistry.load();
  final knightFuture = _track(
    loading,
    scenes.loadScene('assets/characters/Knight.glb'),
  );
  final knight = await knightFuture;
  final openingCount = math.min(_openingBarbarians, barbarianCount);
  final barbarians = <Node>[];
  for (var i = 0; i < openingCount; i++) {
    barbarians.add(
      await _track(loading, scenes.loadScene(_barbarianScene(i))),
    );
  }

  final clips = <String, Animation>{};
  for (final path in _rigFiles) {
    final rig = await _track(loading, scenes.loadScene(path));
    for (final animation in rig.parsedAnimations) {
      clips[animation.name] = animation;
    }
  }
  // Every clip can blend against every other, so they must agree on
  // quaternion sign before instantiation (see anim/hemisphere.dart).
  harmoniseRotationHemispheres(clips.values);
  final assets = CharacterAssets(
    knight: knight,
    barbarians: barbarians,
    clips: clips,
    // Two-handed: the player's sword, the barbarians' axe. The reach sells
    // the wide swings.
    sword: await _track(loading, _loadWeapon('sword_2handed')),
    axe: await _track(loading, _loadWeapon('axe_2handed')),
    // The coloured variant: the plain one is untextured white, which
    // reads as a missing material rather than as a shield.
    shield: await _track(loading, _loadWeapon('shield_square_color')),
  );
  // Two bodies cover the opening wave. The app realizes the reserve only after
  // its first rendered frames, so it cannot hold the loading cover.
  assets._loadReserve = () => _fillBarbarianPool(
    assets,
    scenes,
    openingCount,
    barbarianCount - openingCount,
  );
  return assets;
}

Future<T> _track<T>(ResourceGroup? loading, Future<T> load) =>
    loading?.add(load) ?? load;

Future<void> _fillBarbarianPool(
  CharacterAssets assets,
  SceneRegistry scenes,
  int start,
  int remaining,
) async {
  for (var i = 0; i < remaining; i++) {
    await Future<void>.delayed(Duration.zero);
    try {
      assets.addBarbarian(
        await scenes.loadScene(_barbarianScene(start + i)),
      );
    } on Object catch (error) {
      debugPrint('combat_sample: background barbarian load failed: $error');
      return;
    }
  }
}

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
