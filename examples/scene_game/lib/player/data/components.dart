part of '../player.dart';

/// Tags the player entity.
final class Player implements Tag {
  const Player();
}

final class CrabLegVisual {
  const CrabLegVisual({
    required this.root,
    required this.upper,
    required this.upperSegment,
    required this.lower,
    required this.lowerSegment,
    required this.collapsedPose,
    required this.extendedPose,
    required this.phaseOffset,
    required this.extensionDelay,
    required this.side,
    required this.slot,
  });

  final Node root;
  final Node upper;
  final Node upperSegment;
  final Node lower;
  final Node lowerSegment;
  final CrabLegPose collapsedPose;
  final CrabLegPose extendedPose;
  final double phaseOffset;
  final double extensionDelay;
  final CrabLegSide side;
  final int slot;
}

/// The player's crab legs: player-owned child nodes animated by the
/// player's own gait system. The charge and shield feedback nodes live in
/// [PlayerChargeVisuals] and [PlayerShieldVisuals] — one component per
/// *writing feature*, so the access declarations stay honest and the
/// conflict detector needs no ordering between features that share the
/// player's body.
///
/// All three are built together ([buildPlayerVisuals]) as children of the
/// player root, so the physics-driven sync never disturbs them. Hidden
/// with a zero-scale transform rather than added/removed; materials are
/// unique to the player so per-frame colour changes never leak into other
/// entities.
final class PlayerVisuals {
  PlayerVisuals._({required this.leftLegs, required this.rightLegs});

  factory PlayerVisuals._create() {
    final legMaterial = PhysicallyBasedMaterial()
      ..baseColorFactor = Vector4(0.06, 0.52, 0.75, 1)
      ..metallicFactor = 0.18
      ..roughnessFactor = 0.28
      ..emissiveFactor = Vector4(0.0, 0.08, 0.16, 1);
    return PlayerVisuals._(
      leftLegs: _createCrabLegs(CrabLegSide.left, legMaterial),
      rightLegs: _createCrabLegs(CrabLegSide.right, legMaterial),
    );
  }

  void attachTo(Node root) {
    for (final leg in allLegs) {
      root.add(leg.root);
    }
  }

  final List<CrabLegVisual> leftLegs;
  final List<CrabLegVisual> rightLegs;

  // Visual-only animation state, eased across frames by the gait system.
  double legExtension01 = 0;
  double gaitPhase = 0;

  Iterable<CrabLegVisual> get allLegs sync* {
    yield* leftLegs;
    yield* rightLegs;
  }

  void resetLegs() {
    legExtension01 = 0;
    gaitPhase = 0;
    for (final leg in allLegs) {
      _applyLegPose(leg, leg.collapsedPose, 0, 0, 0);
    }
  }

  static final _legUpperGeometry = CuboidGeometry(
    Vector3(crabLegUpperLength, crabLegThickness, crabLegThickness),
  );
  static final _legLowerGeometry = CuboidGeometry(
    Vector3(
      crabLegLowerLength,
      crabLegThickness * 0.86,
      crabLegThickness * 0.86,
    ),
  );
}

/// The player's charge orb, beam and motes — written only by the
/// projectiles feature's charge VFX system.
final class PlayerChargeVisuals {
  PlayerChargeVisuals._({
    required this.chargeOrb,
    required this.chargeOrbMaterial,
    required this.chargeBeam,
    required this.chargeBeamMaterial,
    required this.chargeMotes,
    required this.chargeMoteMaterial,
  });

  factory PlayerChargeVisuals._create() {
    final chargeOrbMaterial = _blendMaterial(_chargeBaseColor, _chargeEmissive);
    final chargeBeamMaterial = _blendMaterial(
      Vector4(0.4, 0.85, 1.0, 0.5),
      Vector4(0.5, 1.0, 1.4, 1),
    );
    final chargeMoteMaterial = _blendMaterial(
      Vector4(0.7, 0.92, 1.0, 0.8),
      Vector4(0.5, 0.85, 1.0, 1),
    );
    return PlayerChargeVisuals._(
      chargeOrb: Node(
        mesh: Mesh(_orbGeometry, chargeOrbMaterial),
        localTransform: _hiddenAt(
          Vector3(0, 0, -(playerBodyVisualRadius + 0.55)),
        ),
      )..frustumCulled = false,
      chargeOrbMaterial: chargeOrbMaterial,
      chargeBeam: Node(
        mesh: Mesh(_beamGeometry, chargeBeamMaterial),
        localTransform: _hiddenAt(
          Vector3(0, 0, -(playerBodyVisualRadius + 0.3)),
        ),
      )..frustumCulled = false,
      chargeBeamMaterial: chargeBeamMaterial,
      chargeMotes: List<Node>.generate(
        _chargeMoteCount,
        (_) => Node(
          mesh: Mesh(_moteGeometry, chargeMoteMaterial),
          localTransform: _hiddenAt(Vector3.zero()),
        )..frustumCulled = false,
      ),
      chargeMoteMaterial: chargeMoteMaterial,
    );
  }

  void attachTo(Node root) {
    root
      ..add(chargeOrb)
      ..add(chargeBeam);
    for (final mote in chargeMotes) {
      root.add(mote);
    }
  }

  final Node chargeOrb;
  final PhysicallyBasedMaterial chargeOrbMaterial;
  final Node chargeBeam;
  final PhysicallyBasedMaterial chargeBeamMaterial;
  final List<Node> chargeMotes;
  final PhysicallyBasedMaterial chargeMoteMaterial;

  // Visual-only animation state; the blaster resource owns the gameplay
  // truth.
  double chargePhase = 0;
  double chargeShow = 0;

  static final Vector4 _chargeBaseColor = Vector4(0.4, 0.9, 1.0, 0.7);
  static final Vector4 _chargeEmissive = Vector4(0.3, 0.9, 1.2, 1);

  static const int _chargeMoteCount = 10;
  static final _orbGeometry = SphereGeometry(
    radius: 0.3,
    segments: 16,
    rings: 10,
  );
  static final _moteGeometry = SphereGeometry(
    radius: 0.07,
    segments: 8,
    rings: 6,
  );
  // Scaled long in Y into a beam — flutter_scene 0.18 has no cylinder primitive.
  static final _beamGeometry = SphereGeometry(
    radius: 1,
    segments: 12,
    rings: 8,
  );
}

/// The player's shield bubble and activation badge — written only by the
/// collectables feature's shield VFX system.
final class PlayerShieldVisuals {
  PlayerShieldVisuals._({
    required this.shieldBubble,
    required this.shieldBubbleMaterial,
    required this.shieldBadge,
    required this.shieldBadgeMaterial,
  });

  factory PlayerShieldVisuals._create() {
    final shieldBubbleMaterial = _blendMaterial(
      Vector4(0.4, 0.8, 1.0, 0.16),
      Vector4(0.25, 0.6, 1.1, 1),
    );
    final shieldBadgeMaterial = _blendMaterial(
      Vector4(0.7, 0.9, 1.0, 0.8),
      Vector4(0.6, 1.0, 1.4, 1),
    );
    return PlayerShieldVisuals._(
      shieldBubble: Node(
        mesh: Mesh(_bubbleGeometry, shieldBubbleMaterial),
        localTransform: _hiddenAt(Vector3.zero()),
      )..frustumCulled = false,
      shieldBubbleMaterial: shieldBubbleMaterial,
      shieldBadge: Node(
        mesh: Mesh(_badgeGeometry, shieldBadgeMaterial),
        localTransform: _hiddenAt(
          Vector3(
            0,
            playerBodyVisualRadius * 0.6,
            -(playerBodyVisualRadius + 0.4),
          ),
        ),
      )..frustumCulled = false,
      shieldBadgeMaterial: shieldBadgeMaterial,
    );
  }

  void attachTo(Node root) {
    root
      ..add(shieldBubble)
      ..add(shieldBadge);
  }

  final Node shieldBubble;
  final PhysicallyBasedMaterial shieldBubbleMaterial;
  final Node shieldBadge;
  final PhysicallyBasedMaterial shieldBadgeMaterial;

  // Visual-only animation state; the shield resource owns the gameplay
  // truth.
  double shieldPhase = 0;
  double shieldShow = 0;
  double badgePop = 0;

  /// Lets the shield VFX system fire the pop on the inactive -> active edge.
  bool shieldWasActive = false;

  static final _bubbleGeometry = SphereGeometry(
    radius: shieldBubbleRadius,
    segments: 24,
    rings: 16,
  );
  static final _badgeGeometry = SphereGeometry(
    radius: 0.22,
    segments: 12,
    rings: 8,
  );
}

/// Builds the player's full visual suite. One construction site so the
/// bundle stays a list of parts, each owned (written) by exactly one
/// feature.
(PlayerVisuals, PlayerChargeVisuals, PlayerShieldVisuals)
    buildPlayerVisuals() => (
          PlayerVisuals._create(),
          PlayerChargeVisuals._create(),
          PlayerShieldVisuals._create(),
        );

PhysicallyBasedMaterial _blendMaterial(Vector4 base, Vector4 emissive) {
  return PhysicallyBasedMaterial()
    ..baseColorFactor = base
    ..emissiveFactor = emissive
    ..metallicFactor = 0
    ..roughnessFactor = 0.2
    ..alphaMode = AlphaMode.blend;
}

/// A zero-scale transform at [position]: present in the tree but invisible.
Matrix4 _hiddenAt(Vector3 position) =>
    Matrix4.translation(position)..scaleByDouble(0, 0, 0, 1);

List<CrabLegVisual> _createCrabLegs(CrabLegSide side, Material material) {
  return List<CrabLegVisual>.generate(crabLegsPerSide, (slot) {
    final upperSegment = Node(
      mesh: Mesh(PlayerVisuals._legUpperGeometry, material),
    )..frustumCulled = false;
    final lowerSegment = Node(
      mesh: Mesh(PlayerVisuals._legLowerGeometry, material),
    )..frustumCulled = false;
    final lower = Node()
      ..frustumCulled = false
      ..add(lowerSegment);
    final upper = Node()
      ..frustumCulled = false
      ..add(upperSegment)
      ..add(lower);
    final root = Node()..frustumCulled = false;
    root.add(upper);
    final collapsed = crabLegPoseFor(side, slot, extended: false);
    final extended = crabLegPoseFor(side, slot, extended: true);
    final leg = CrabLegVisual(
      root: root,
      upper: upper,
      upperSegment: upperSegment,
      lower: lower,
      lowerSegment: lowerSegment,
      collapsedPose: collapsed,
      extendedPose: extended,
      phaseOffset: crabLegPhaseOffset(side, slot),
      extensionDelay: slot * crabLegExtensionStagger,
      side: side,
      slot: slot,
    );
    _applyLegPose(leg, collapsed, 0, 0, 0);
    return leg;
  }, growable: false);
}

void _applyLegPose(
  CrabLegVisual leg,
  CrabLegPose pose,
  double lift,
  double stride,
  double bend,
) {
  final root = leg.root.localTransform
    ..setIdentity()
    ..setTranslationRaw(pose.rootX, pose.rootY + lift, pose.rootZ + stride)
    ..rotateY(pose.rootYaw)
    ..rotateZ(pose.rootRoll);
  leg.root.localTransform = root;

  final sign = leg.side.sign.toDouble();
  final upperScale = pose.upperScale;
  final upper = leg.upper.localTransform
    ..setIdentity()
    ..rotateZ(pose.upperAngle + sign * bend * 0.35);
  leg.upper.localTransform = upper;

  final upperSegment = leg.upperSegment.localTransform
    ..setIdentity()
    ..setTranslationRaw(sign * crabLegUpperLength * upperScale * 0.5, 0, 0)
    ..scaleByDouble(upperScale, 1, 1, 1);
  leg.upperSegment.localTransform = upperSegment;

  final lowerScale = pose.lowerScale;
  final lower = leg.lower.localTransform
    ..setIdentity()
    ..setTranslationRaw(
      sign * crabLegUpperLength * upperScale,
      -crabLegThickness * 0.25,
      0,
    )
    ..rotateZ(pose.lowerAngle - sign * bend);
  leg.lower.localTransform = lower;

  final lowerSegment = leg.lowerSegment.localTransform
    ..setIdentity()
    ..setTranslationRaw(sign * crabLegLowerLength * lowerScale * 0.5, 0, 0)
    ..scaleByDouble(lowerScale, 1, 1, 1);
  leg.lowerSegment.localTransform = lowerSegment;
}
