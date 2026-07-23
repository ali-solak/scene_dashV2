import 'package:data_assets/data_assets.dart';
import 'package:flutter_scene/build_hooks.dart';
import 'package:hooks/hooks.dart';

const _sceneOutput = 'build/scenes/';
const _barbarianSource = 'assets/characters/Barbarian.glb';
const _barbarianSlots = 10;

String _sceneAssetName(String relativeScenePath) =>
    'flutter_scene/scene/$relativeScenePath';

void main(List<String> args) async {
  await build(args, (input, output) async {
    buildScenes(
      buildInput: input,
      buildOutput: output,
      outputDirectory: _sceneOutput,
      assetMode: SceneAssetMode.dataAssetsRequired,
      inputFilePaths: const [
        'assets/characters/Knight.glb',
        _barbarianSource,
        'assets/animation/Rig_Medium_General.glb',
        'assets/animation/Rig_Medium_MovementBasic.glb',
        'assets/animation/Rig_Medium_MovementAdvanced.glb',
        'assets/animation/Rig_Medium_CombatMelee.glb',
        'assets/animation/Rig_Medium_Special.glb',
      ],
    );

    final barbarianFile = input.packageRoot.resolve(
      '${_sceneOutput}assets/characters/Barbarian.fsceneb',
    );
    for (var i = 0; i < _barbarianSlots; i++) {
      output.assets.data.add(
        DataAsset(
          package: input.packageName,
          name: _sceneAssetName('assets/characters/Barbarian_$i.fsceneb'),
          file: barbarianFile,
        ),
      );
    }

    await buildMaterials(
      buildInput: input,
      buildOutput: output,
      assetMode: MaterialAssetMode.dataAssetsRequired,
    );
  });
}
