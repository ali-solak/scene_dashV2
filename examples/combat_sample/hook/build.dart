// One asset per source file. The barbarian pool needs INDEPENDENT skinned
// instances, but per-slot DataAsset aliases of the same `.fsceneb` are the
// wrong tool: they ship the same 4.6M scene once per slot (~46MB of web
// payload). Instead the pool reads the one asset's bytes and realizes each
// instance with its own resource realizer (see `character_assets.dart`),
// which sidesteps flutter_scene #257 (template-shared `SkinnedGeometry`
// renders a pack as one body) at zero payload cost.
import 'package:flutter_scene/build_hooks.dart';
import 'package:hooks/hooks.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    buildScenes(
      buildInput: input,
      buildOutput: output,
      outputDirectory: 'build/scenes/',
      assetMode: SceneAssetMode.dataAssetsRequired,
      inputFilePaths: const [
        'assets/characters/Knight.glb',
        'assets/characters/Barbarian.glb',
        'assets/animation/Rig_Medium_General.glb',
        'assets/animation/Rig_Medium_MovementBasic.glb',
        'assets/animation/Rig_Medium_MovementAdvanced.glb',
        'assets/animation/Rig_Medium_CombatMelee.glb',
        'assets/animation/Rig_Medium_Special.glb',
      ],
    );

    await buildMaterials(
      buildInput: input,
      buildOutput: output,
      assetMode: MaterialAssetMode.dataAssetsRequired,
    );
  });
}
