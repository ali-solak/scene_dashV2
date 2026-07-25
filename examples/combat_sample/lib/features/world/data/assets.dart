library;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_scene/scene.dart';

class WorldAssets {
  WorldAssets({
    this.groundMaterial,
    this.grassMaterial,
    this.dissolveMaterial,
    this.oceanMaterial,
    this.lavaMaterial,
    this.barrierMaterial,
  });

  WorldAssets.none()
    : groundMaterial = null,
      grassMaterial = null,
      dissolveMaterial = null,
      oceanMaterial = null,
      lavaMaterial = null,
      barrierMaterial = null;

  final Material? groundMaterial;
  final PreprocessedMaterial? grassMaterial;

  /// The death dissolve, threshold-driven per frame by the enemies'
  /// material system.
  final PreprocessedMaterial? dissolveMaterial;

  /// The sea below the cliff, wave `time` driven by the wind clock.
  final PreprocessedMaterial? oceanMaterial;

  /// The lava pit's crust, `time`/`heat` driven by the pit's own clock.
  final PreprocessedMaterial? lavaMaterial;

  final PreprocessedMaterial? barrierMaterial;
}

/// Loads every stage asset. Call after `Scene.initializeStaticResources()`;
/// imports upload geometry and need the GPU context.
Future<WorldAssets> loadWorldAssets({ResourceGroup? loading}) async {
  final registry = await FmatMaterialRegistry.load();
  final ground = await _track(loading, _load(registry, 'ground_noise'));
  final grass = await _track(loading, _load(registry, 'grass_sway'));
  final dissolve = await _track(loading, _load(registry, 'dissolve'));
  final ocean = await _track(loading, _load(registry, 'ocean'));
  final lava = await _track(loading, _load(registry, 'lava'));
  final barrier = await _track(loading, _load(registry, 'barrier'));
  return WorldAssets(
    groundMaterial: ground,
    grassMaterial: grass,
    dissolveMaterial: dissolve,
    oceanMaterial: ocean,
    lavaMaterial: lava,
    barrierMaterial: barrier,
  );
}

Future<T> _track<T>(ResourceGroup? loading, Future<T> load) =>
    loading?.add(load) ?? load;

Future<PreprocessedMaterial?> _load(
  FmatMaterialRegistry registry,
  String name,
) async {
  try {
    return await registry.loadMaterial('assets/materials/$name.fmat');
  } on Object catch (error) {
    debugPrint('combat_sample: $name.fmat unavailable, using fallback: $error');
    return null;
  }
}
