// Compiles the `.fmat` materials under assets/ into a Flutter GPU shader
// bundle registered as DataAssets, loadable by source path with
// `loadFmatMaterial` (and hot-reloadable). Requires
// `flutter config --enable-dart-data-assets` on a master-channel build.
//
// `buildScenes` is deliberately omitted: models load through the 0.19
// runtime glTF importer (`Node.fromGlbAsset`), not the offline `.fsceneb`
// pipeline.
import 'package:flutter_scene/build_hooks.dart';
import 'package:hooks/hooks.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    await buildMaterials(
      buildInput: input,
      buildOutput: output,
      assetMode: MaterialAssetMode.dataAssetsRequired,
    );
  });
}
