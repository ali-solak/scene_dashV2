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

/// One cooked asset serves the whole pool, but each barbarian must be
/// realized with its OWN resource realizer, not through
/// [SceneRegistry.loadScene]: instances realized off one cached template
/// share their `SkinnedGeometry`, and per-frame joint textures are written
/// through it, so a pack loaded that way renders as a single body
/// (flutter_scene #257 — the same defect `clone()` has). The fix (PR #263,
/// joint state per render item) is merged upstream but unreleased; once it
/// ships, collapse this back to `scenes.loadScene(_barbarianScene)` per
/// instance and the pack shares GPU geometry/textures again.
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
  final scenes = await SceneRegistry.load();

  // The knight, the barbarian document, the five rigs and the three
  // weapons are all independent of each other: start them together and
  // collect below, so the load costs its slowest member rather than the
  // sum of all of them.
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
  // Parsed once; realized once per barbarian (see [_barbarianScene]).
  final barbarianDocument = readFsceneb(await documentBytes);
  final openingCount = math.min(_openingBarbarians, barbarianCount);
  final barbarians = <Node>[];
  for (var i = 0; i < openingCount; i++) {
    barbarians.add(await _track(loading, realizeSceneAsync(barbarianDocument)));
  }

  // Awaited in list order even though they loaded concurrently: the rigs
  // share clip names (every one carries a T-Pose), so a later file is
  // meant to win, and that only holds if insertion follows [_rigFiles].
  final clips = <String, Animation>{};
  for (final rigFuture in rigFutures) {
    for (final animation in (await rigFuture).parsedAnimations) {
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
    sword: await swordFuture,
    axe: await axeFuture,
    // The coloured variant: the plain one is untextured white, which
    // reads as a missing material rather than as a shield.
    shield: await shieldFuture,
  );
  // Two bodies cover the opening wave. The app realizes the reserve only after
  // its first rendered frames, so it cannot hold the loading cover.
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
