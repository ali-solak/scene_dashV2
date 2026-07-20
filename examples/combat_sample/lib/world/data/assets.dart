/// GPU-backed stage assets, loaded once in `main` before boot (imports and
/// material compilation are async; systems are not) and handed to
/// [installWorld] as a resource. Headless games use [WorldAssets.none] —
/// every consumer is scene-gated.
library;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_scene/scene.dart';

// The KayKit nature-pack glTFs were dropped: they carry Khronos material
// extensions the 0.19 runtime importer rejects. The forest is procedural
// now (vfx/forest.dart); only the authored .fmat materials load here.

class WorldAssets {
  WorldAssets({
    this.groundMaterial,
    this.grassMaterial,
    this.dissolveMaterial,
    this.oceanMaterial,
    this.lavaMaterial,
    this.barrierMaterial,
  });

  /// The headless stand-in: no materials. Scene-gated systems never touch
  /// it.
  WorldAssets.none()
      : groundMaterial = null,
        grassMaterial = null,
        dissolveMaterial = null,
        oceanMaterial = null,
        lavaMaterial = null,
        barrierMaterial = null;

  /// The authored `.fmat` materials, or null when the DataAssets bundle is
  /// unavailable (consumers fall back to plain PBR and the stage still
  /// boots).
  final Material? groundMaterial;
  final PreprocessedMaterial? grassMaterial;

  /// The death dissolve, threshold-driven per frame by the enemies'
  /// material system.
  final PreprocessedMaterial? dissolveMaterial;

  /// The sea below the cliff, wave `time` driven by the wind clock.
  final PreprocessedMaterial? oceanMaterial;

  /// The lava pit's crust, `time`/`heat` driven by the pit's own clock.
  final PreprocessedMaterial? lavaMaterial;

  /// The shield's bubble: `charge` from what the barrier has left,
  /// `hit`/`hit_dir` from the last block. One instance, shared — there is
  /// only ever one barrier, because there is only ever one player.
  final PreprocessedMaterial? barrierMaterial;
}

/// Loads every stage asset. Call after `Scene.initializeStaticResources()`;
/// imports upload geometry and need the GPU context.
Future<WorldAssets> loadWorldAssets() async {
  return WorldAssets(
    groundMaterial: await _load('ground_noise'),
    grassMaterial: await _load('grass_sway'),
    dissolveMaterial: await _load('dissolve'),
    oceanMaterial: await _load('ocean'),
    lavaMaterial: await _load('lava'),
    barrierMaterial: await _load('barrier'),
  );
}

/// Loads one `.fmat`, or null with a NAMED complaint.
///
/// Deliberately one try per material rather than one around the batch:
/// batching means a single bad shader takes out every material after it
/// in the list, and the log names none of them. Two authored materials
/// have already failed silently in this sample's history (see NOTES.md
/// B4) — the console should say which one and why.
///
/// Common causes, in order of likelihood:
///  * the bundle is STALE — a newly added `.fmat` is compiled by
///    `hook/build.dart` at BUILD time, so a hot restart will not pick it
///    up. Stop the app and run it again.
///  * `flutter config --enable-dart-data-assets` was never run.
///  * the shader does not compile; the error below is the compiler's.
Future<PreprocessedMaterial?> _load(String name) async {
  try {
    return await loadFmatMaterial('assets/materials/$name.fmat');
  } on Object catch (error) {
    debugPrint('combat_sample: $name.fmat unavailable, using fallback: $error');
    return null;
  }
}
