library;

import 'dart:async' show unawaited;
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_scene/fscene.dart'
    show SceneDocument, readFsceneb, realizeSceneAsync;
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

/// Each barbarian needs independent skin data.
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
  final documentBytes = _assetBytes(scenes.resolveKey(_barbarianScene));
  final rigFutures = [
    for (final path in _rigFiles) _track(loading, scenes.loadScene(path)),
  ];
  final swordFuture = _track(loading, _loadWeapon('sword_2handed'));
  final axeFuture = _track(loading, _loadWeapon('axe_2handed'));
  final shieldFuture = _track(loading, _loadWeapon('shield_square_color'));

  final knight = await knightFuture;
  // Realize each barbarian from one document.
  final barbarianDocument = readFsceneb(await documentBytes);
  final openingCount = math.min(_openingBarbarians, barbarianCount);
  final barbarians = <Node>[];
  for (var i = 0; i < openingCount; i++) {
    barbarians.add(await _track(loading, realizeSceneAsync(barbarianDocument)));
  }

  // Merge clips in rig order.
  final clips = <String, Animation>{};
  for (final rigFuture in rigFutures) {
    for (final animation in (await rigFuture).parsedAnimations) {
      clips[animation.name] = animation;
    }
  }
  // Align clip rotations before blending.
  harmoniseRotationHemispheres(clips.values);
  final assets = CharacterAssets(
    knight: knight,
    barbarians: barbarians,
    clips: clips,
    // Two handed weapons.
    sword: await swordFuture,
    axe: await axeFuture,
    // Colored shield.
    shield: await shieldFuture,
  );
  // Load reserve bodies after startup.
  assets._loadReserve = () => _fillBarbarianPool(
    assets,
    barbarianDocument,
    barbarianCount - openingCount,
  );
  return assets;
}

Future<T> _track<T>(ResourceGroup? loading, Future<T> load) =>
    loading?.add(load) ?? load;

Future<void> _fillBarbarianPool(
  CharacterAssets assets,
  SceneDocument document,
  int remaining,
) async {
  for (var i = 0; i < remaining; i++) {
    await Future<void>.delayed(Duration.zero);
    try {
      assets.addBarbarian(await realizeSceneAsync(document));
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
