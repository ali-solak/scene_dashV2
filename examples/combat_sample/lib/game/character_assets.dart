/// The characters and their clips, loaded once in `main` before boot (the
/// 0.19 runtime importer is async; systems are not) and inserted as a
/// resource. KayKit characters carry no animations — every clip lives in
/// the shared `Rig_Medium_*.glb` carriers and binds onto a character's
/// skeleton by node name (docs/asset_inventory.md).
///
/// Headless games never insert this; the attach systems fall back to the
/// graybox capsules when it is absent.
library;

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
  // Carries EXPERIMENTAL_Medium_Transform (1.00 s) — the giant's
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

  /// Model instances. The knight is used directly (one player); each
  /// barbarian gets its OWN import — `Node.clone()` of a skinned model
  /// broke the second clone's skin binding (an invisible body under a
  /// visible, unskinned axe), so instances never share a skeleton.
  ///
  /// Because they cannot be cloned, waves RECYCLE them: [takeBarbarian]
  /// lends one out, [releaseBarbarian] takes it back when the enemy
  /// despawns. The pool size is therefore the concurrent-barbarian cap.
  final Node knight;
  final List<Node> barbarians;

  late final List<bool> _lent = List<bool>.filled(barbarians.length, false);

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

  /// Weapon templates for the `handslot.r` joint (null when their glTFs
  /// fail to import — the fight goes bare-handed, not down).
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

Future<CharacterAssets> loadCharacterAssets({
  required int barbarianCount,
}) async {
  final knight = await Node.fromGlbAsset('assets/characters/Knight.glb');
  final barbarians = <Node>[
    for (var i = 0; i < barbarianCount; i++)
      await Node.fromGlbAsset('assets/characters/Barbarian.glb'),
  ];
  final clips = <String, Animation>{};
  for (final path in _rigFiles) {
    final rig = await Node.fromGlbAsset(path);
    for (final animation in rig.parsedAnimations) {
      clips[animation.name] = animation;
    }
  }
  // Every clip here can end up blended against every other, so they all
  // have to agree on quaternion sign before any of them is instantiated.
  // This is what lets the fades below be real crossfades instead of the
  // hard snap the pancake forced (see anim/hemisphere.dart).
  harmoniseRotationHemispheres(clips.values);
  return CharacterAssets(
    knight: knight,
    barbarians: barbarians,
    clips: clips,
    // Two-handed: a longer blade sells the reach and the heavy swings.
    sword: await _loadWeapon('sword_2handed'),
    axe: await _loadWeapon('axe_2handed'),
    // The coloured variant: the plain one is untextured white, which
    // reads as a missing material rather than as a shield.
    shield: await _loadWeapon('shield_square_color'),
  );
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
