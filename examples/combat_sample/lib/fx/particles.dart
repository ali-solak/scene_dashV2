/// The slice's single import surface for flutter_scene's particle system.
///
/// flutter_scene 0.19 ships these under `lib/src/` only, so the
/// implementation imports are confined here; when upstream barrels them,
/// only this file changes.
///
/// Import with a prefix (`as fx`): the particle `SphereShape`/`BoxShape`
/// collide with the physics collider shapes in the main barrel.
library;

// ignore_for_file: implementation_imports
export 'package:flutter_scene/src/components/particle_emitter_component.dart';
export 'package:flutter_scene/src/particles/distribution.dart';
export 'package:flutter_scene/src/particles/emitter_shape.dart';
export 'package:flutter_scene/src/particles/particle_module.dart';
export 'package:flutter_scene/src/particles/particle_storage.dart';
export 'package:flutter_scene/src/particles/particle_system.dart';
export 'package:flutter_scene/src/particles/spawner.dart';
