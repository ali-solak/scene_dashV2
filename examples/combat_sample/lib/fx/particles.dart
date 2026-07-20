/// The slice's single import surface for flutter_scene's particle system.
///
/// flutter_scene 0.19 ships `ParticleEmitterComponent` and its
/// configuration types under `lib/src/` only — upstream's own
/// `TODO(particles)` defers barreling them until the authoring API
/// settles. Concentrating the implementation imports here keeps the
/// exception to one file; when upstream exports them from
/// `package:flutter_scene/scene.dart`, this file's exports flip to the
/// barrel and nothing else changes.
///
/// Import with a prefix (`as fx`) — the particle `SphereShape`/`BoxShape`
/// emitter shapes collide with the physics collider shapes of the same
/// names in the main barrel.
library;

// ignore_for_file: implementation_imports
export 'package:flutter_scene/src/components/particle_emitter_component.dart';
export 'package:flutter_scene/src/particles/distribution.dart';
export 'package:flutter_scene/src/particles/emitter_shape.dart';
export 'package:flutter_scene/src/particles/particle_module.dart';
export 'package:flutter_scene/src/particles/particle_storage.dart';
export 'package:flutter_scene/src/particles/particle_system.dart';
export 'package:flutter_scene/src/particles/spawner.dart';
