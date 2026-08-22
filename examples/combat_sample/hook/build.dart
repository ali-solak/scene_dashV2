import 'package:flutter_scene/build_hooks.dart';
import 'package:hooks/hooks.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    buildScenes(
      buildInput: input,
      buildOutput: output,
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
    );
  });
}
