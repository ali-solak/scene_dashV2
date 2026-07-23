library;

import 'dart:async' show unawaited;
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show rootBundle;

import '../anim/hemisphere.dart';
import 'package:flutter_scene/scene.dart';

/// Rig files this slice actually uses (general/hits/deaths, locomotion,
/// dodges/strafes, melee).
const List<String> _rigFiles = [
  'assets/animation/Rig_Medium_General.glb',
  'assets/animation/Rig_Medium_MovementBasic.glb',
  'assets/animation/Rig_Medium_MovementAdvanced.glb',
  'assets/animation/Rig_Medium_CombatMelee.glb',
  // Carries EXPERIMENTAL_Medium_Transform (1.00 s): the giant's
  // transformation.
  'assets/animation/Rig_Medium_Special.glb',
];

class CharacterAssets {
  CharacterAssets({
    required this.knight,
    required this.barbarians,
    required this.clips,
    this.sword,
    this.axe,
    this.shield,
  });

  /// Model instances. Each barbarian gets its own import: `Node.clone()`
  /// of a skinned model broke the clone's skin binding, so waves recycle
  /// instead ([takeBarbarian] lends, [releaseBarbarian] returns). Pool
  /// size is the concurrent-barbarian cap.
  final Node knight;
  final List<Node> barbarians;

  late final List<bool> _lent = List<bool>.filled(
    barbarians.length,
    false,
    growable: true,
  );

  /// Appends a background-loaded model to the pool: a few are warmed at
  /// boot, the rest stream in behind the title screen so the loading
  /// screen never freezes on ten glTF imports.
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

  /// Returns a model to the pool and unparents it, so the next borrower
  /// can hang it under a fresh wrapper.
  void releaseBarbarian(int index) {
    if (index < 0 || index >= _lent.length) return;
    _lent[index] = false;
    barbarians[index].detach();
  }

  /// Weapon templates for the `handslot.r` joint (each wielder clones its
  /// own). The player carries the [sword]; every barbarian carries the
  /// [axe]. Null when the glTF fails to import: the fight goes
  /// bare-handed, not down.
  final Node? sword;
  final Node? axe;

  /// The shield, for `handslot.l`. Unlike the weapons this is not worn
  /// from the start: the skill parents a clone while its barrier is up
  /// and takes it back off when the barrier breaks.
  final Node? shield;

  /// Every parsed rig animation by clip name.
  final Map<String, Animation> clips;

  Animation clip(String name) {
    final animation = clips[name];
    if (animation == null) {
      throw StateError('rig clip "$name" not found');
    }
    return animation;
  }
}

/// Barbarians warmed synchronously at boot. Early waves are small
/// ([baseWaveEnemies]), so this covers the opening; a wave that outruns
/// the background fill borrows graybox capsules for a beat.
const int _warmBarbarians = 4;

Future<CharacterAssets> loadCharacterAssets({
  required int barbarianCount,
}) async {
  final knight = await Node.fromGlbAsset('assets/characters/Knight.glb');
  final warm = math.min(_warmBarbarians, barbarianCount);
  final barbarians = <Node>[
    for (var i = 0; i < warm; i++)
      await Node.fromGlbAsset('assets/characters/Barbarian.glb'),
  ];
  final clips = <String, Animation>{};
  for (final path in _rigFiles) {
    final rig = await Node.fromGlbAsset(path);
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
    sword: await _loadWeapon('sword_2handed'),
    axe: await _loadWeapon('axe_2handed'),
    // The coloured variant: the plain one is untextured white, which
    // reads as a missing material rather than as a shield.
    shield: await _loadWeapon('shield_square_color'),
  );
  // The rest of the pool fills in the background, one import per turn of
  // the event loop, so a frame renders between each.
  unawaited(_fillBarbarianPool(assets, barbarianCount - warm));
  return assets;
}

/// Streams [remaining] more barbarians into [assets]' pool, yielding between
/// each so the load never blocks a frame.
Future<void> _fillBarbarianPool(CharacterAssets assets, int remaining) async {
  for (var i = 0; i < remaining; i++) {
    try {
      final node = await Node.fromGlbAsset('assets/characters/Barbarian.glb');
      assets.addBarbarian(node);
    } on Object catch (error) {
      debugPrint('combat_sample: background barbarian load failed: $error');
      return;
    }
  }
}

Future<Uint8List> _weaponBytes(String uri) async {
  final data = await rootBundle.load('assets/character_assets/$uri');
  return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
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
