part of '../world.dart';

/// Configures the scene look directly on the `Scene` resource and builds
/// the static ramp — a plain scene node, not an ECS entity, since it never
/// moves. Runs once at startup; a no-op in a headless game (timing tests),
/// where there is no scene to dress.
void setupWorld(World world) {
  final scene = world.resource<Scene>();
  scene
    ..skybox = Skybox(GradientSkySource())
    ..environment = EnvironmentMap.studio()
    ..directionalLight = DirectionalLight(
      direction: Vector3(-0.45, -1.0, -0.35),
      color: Vector3(1.0, 0.94, 0.84),
      intensity: 4.4,
      castsShadow: true,
    )
    ..toneMapping = ToneMappingMode.aces
    ..exposure = 1.06;
  scene.postProcess.colorGrading
    ..enabled = true
    ..contrast = 1.04
    ..saturation = 1.05
    ..temperature = 0.08;
  scene.postProcess.bloom
    ..enabled = false
    ..threshold = 1.55
    ..intensity = 0.12
    ..scatter = 0.45;
  scene.postProcess.vignette
    ..enabled = true
    ..intensity = 0.24
    ..radius = 0.82
    ..smoothness = 0.62;

  scene
    ..antiAliasingMode = AntiAliasingMode.auto
    ..renderScale = 1.0;
  // SSAO is off by default and requires the PerspectiveCamera this game uses.
  scene.ambientOcclusion
    ..enabled = true
    ..intensity = 1.1
    ..radius = 0.4;

  final ramp =
      Node(
          mesh: Mesh(
            CuboidGeometry(Vector3(rampWidth, rampThickness, rampLength)),
            PhysicallyBasedMaterial()
              ..baseColorFactor = Vector4(0.24, 0.27, 0.32, 1)
              ..metallicFactor = 0.22
              ..roughnessFactor = 0.36,
          ),
          localTransform: Matrix4.rotationX(rampInclineRadians),
        )
        ..addComponent(RapierRigidBody(type: BodyType.fixed))
        ..addComponent(
          RapierCollider(
            shape: BoxShape(
              halfExtents: Vector3(
                rampWidth / 2,
                rampThickness / 2,
                rampLength / 2,
              ),
            ),
            collisionLayer: PhysicsLayers.platform,
          ),
        );

  _addLaneStripes(ramp);
  scene.root.add(ramp);
}

void _addLaneStripes(Node ramp) {
  final stripe = PhysicallyBasedMaterial()
    ..baseColorFactor = Vector4(0.9, 0.85, 0.5, 1)
    ..metallicFactor = 0.08
    ..roughnessFactor = 0.24
    ..emissiveFactor = Vector4(0.28, 0.22, 0.07, 1);
  const count = 7;
  final geometry = CuboidGeometry(Vector3(rampWidth * 0.94, 0.06, 0.35));
  for (var i = 1; i < count; i++) {
    final z = -rampLength / 2 + rampLength * i / count;
    ramp.add(
      Node(
        mesh: Mesh(geometry, stripe),
        localTransform: Matrix4.translation(
          Vector3(0, rampThickness / 2 + 0.04, z),
        ),
      ),
    );
  }
}
