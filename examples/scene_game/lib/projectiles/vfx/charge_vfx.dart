part of '../projectiles.dart';

/// Drives the player's charge orb, plasma load and orbiting motes from the
/// [Blaster], the sole source of charge truth. Mutates player-owned nodes
/// and unique materials in place. The plasma emitter spirals energy into
/// the orb and the motes ride a rising, converging vortex that tightens
/// and quickens as the charge builds.
void updateChargeVisuals(World world) {
  final plasma = world.singleOrNull<ChargePlasmaEmitter>();
  final player = world
      .query2<SceneNode, PlayerChargeVisuals>(require: const [Player])
      .firstOrNull;
  final blaster = world.singleOrNull<Blaster>();
  if (player == null || blaster == null) {
    plasma?.spawner.rate = 0;
    return;
  }
  final v = player.$3;
  final c = blaster.charge01;
  final charging = blaster.isCharging;

  // The plasma emitter rides a scene-gated process entity (absent
  // headless); parent it to the current player on first sight each run
  // and let charge throttle it.
  if (plasma != null) {
    final root = player.$2.node;
    final plasmaNode = plasma.node;
    if (plasmaNode.parent != root) {
      plasmaNode.parent?.remove(plasmaNode);
      root.add(plasmaNode);
    }
    plasma.spawner.rate = charging
        ? chargePlasmaRateMin +
              (chargePlasmaRateMax - chargePlasmaRateMin) * c
        : 0;
  }

  v.chargePhase += world.dt * (6 + 10 * c);
  // Eased show factor so release/cancel shrinks the orb and beam cleanly.
  final show = v.chargeShow = approach(
    v.chargeShow,
    charging ? 1.0 : 0.0,
    world.dt * 12,
  );

  final pulse = 1 + 0.08 * math.sin(v.chargePhase);
  final flash = (charging && c > 0.82)
      ? 0.75 + 0.25 * math.sin(v.chargePhase * 3)
      : 1.0;
  final mix = c * c; // eased colour blend toward the charged violet

  // The beam's vertical span doubles as the extent the motes ride along.
  final beamBaseY = playerBodyVisualRadius * 1.05;
  final beamHeight = (0.25 + 1.45 * c) * show;

  _updateChargeOrb(v, c: c, show: show, mix: mix, flash: flash, pulse: pulse);
  _updateChargeBeam(
    v,
    c: c,
    show: show,
    mix: mix,
    flash: flash,
    pulse: pulse,
    beamBaseY: beamBaseY,
    beamHeight: beamHeight,
  );
  _updateChargeMotes(
    v,
    c: c,
    show: show,
    mix: mix,
    flash: flash,
    beamBaseY: beamBaseY,
    beamHeight: beamHeight,
  );
}

void _updateChargeOrb(
  PlayerChargeVisuals v, {
  required double c,
  required double show,
  required double mix,
  required double flash,
  required double pulse,
}) {
  // The orb is the plasma load's core: it swells with charge as the
  // spiraling motes feed it, breathing with the shared pulse.
  v.chargeOrb.setLocalUniform(
    0,
    0,
    -(playerBodyVisualRadius + 0.55),
    (0.14 + 0.3 * c) * show * pulse,
  );
  v.chargeOrbMaterial.emissiveFactor = Vector4(
    (0.3 + 0.85 * mix) * flash,
    (0.9 - 0.35 * mix) * flash,
    (1.2 + 0.2 * mix) * flash,
    1,
  );
  v.chargeOrbMaterial.baseColorFactor = Vector4(
    0.4 + 0.45 * mix,
    0.9 - 0.2 * mix,
    1.0,
    (0.6 + 0.4 * c) * show,
  );
}

/// The energy core: a slim bright column at the muzzle — kept crisp and
/// thin so it reads as the plasma's spine, not the old wide cone.
void _updateChargeBeam(
  PlayerChargeVisuals v, {
  required double c,
  required double show,
  required double mix,
  required double flash,
  required double pulse,
  required double beamBaseY,
  required double beamHeight,
}) {
  final beamThick = (0.035 + 0.05 * c) * show * pulse;
  v.chargeBeam.setLocalTRS(
    0,
    beamBaseY + beamHeight * 0.5,
    0,
    beamThick,
    beamHeight * 0.5,
    beamThick,
  );
  v.chargeBeamMaterial.emissiveFactor = Vector4(
    (0.5 + 0.8 * mix) * flash,
    (1.1 - 0.3 * mix) * flash,
    (1.6 + 0.1 * mix) * flash,
    1,
  );
  v.chargeBeamMaterial.baseColorFactor = Vector4(
    0.45 + 0.4 * mix,
    0.88,
    1.0,
    (0.6 + 0.35 * c) * show,
  );
}

/// The signature charge twirl: motes orbit the muzzle in a rising helix,
/// wobbling as they climb the beam. Player-owned nodes, mutated in place;
/// no scene resource needed, so it runs the same in a headless test.
void _updateChargeMotes(
  PlayerChargeVisuals v, {
  required double c,
  required double show,
  required double mix,
  required double flash,
  required double beamBaseY,
  required double beamHeight,
}) {
  v.chargeMoteMaterial.baseColorFactor = Vector4(
    0.62 + 0.2 * mix,
    0.9 - 0.12 * mix,
    1.0,
    (0.35 + 0.45 * c) * show,
  );
  v.chargeMoteMaterial.emissiveFactor = Vector4(
    (0.45 + 0.55 * mix) * flash,
    (0.8 - 0.18 * mix) * flash,
    (1.0 + 0.22 * mix) * flash,
    1,
  );

  final moteCount = v.chargeMotes.length;
  final moteRadius = 0.34 + 0.12 * c;
  final riseExtent = math.max(beamHeight, 0.1);
  for (var i = 0; i < moteCount; i++) {
    final offset = i / moteCount;
    final rise = (offset + v.chargePhase * 0.035) % 1.0;
    final angle = v.chargePhase * (0.45 + 0.05 * i) + offset * math.pi * 2;
    final wobble = 1 + 0.18 * math.sin(v.chargePhase * 1.3 + i);
    final x = math.cos(angle) * moteRadius * wobble;
    final z = math.sin(angle) * moteRadius * wobble;
    final y = beamBaseY + riseExtent * rise;
    final size = (0.65 + 0.35 * math.sin(v.chargePhase + i)) * show;
    v.chargeMotes[i].setLocalUniform(x, y, z, size);
  }
}
