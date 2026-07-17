part of '../projectiles.dart';

/// Drives the player's charge orb, beam and orbiting motes from the
/// [Blaster], the sole source of charge truth. Mutates player-owned nodes
/// and unique materials in place. The motes spiral as a rising, converging
/// vortex that tightens and quickens as the charge builds.
void updateChargeVisuals(World world) {
  final visuals = world
      .query<PlayerChargeVisuals>(require: const [Player])
      .firstOrNull;
  if (visuals == null) return;
  final v = visuals.$2;
  final blaster = world.singleOrNull<Blaster>();
  if (blaster == null) return;
  final c = blaster.charge01;
  final charging = blaster.isCharging;

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

  _updateChargeOrb(v, c: c, show: show, mix: mix, flash: flash);
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
}) {
  v.chargeOrb.setLocalUniform(0, 0, 0, 0);
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
  final beamThick = (0.06 + 0.08 * c) * show * pulse;
  v.chargeBeam.setLocalTRS(
    0,
    beamBaseY + beamHeight * 0.5,
    0,
    beamThick,
    beamHeight * 0.5,
    beamThick,
  );
  v.chargeBeamMaterial.emissiveFactor = Vector4(
    (0.4 + 0.7 * mix) * flash,
    (1.0 - 0.3 * mix) * flash,
    (1.4 + 0.1 * mix) * flash,
    1,
  );
  v.chargeBeamMaterial.baseColorFactor = Vector4(
    0.45 + 0.4 * mix,
    0.88,
    1.0,
    (0.5 + 0.4 * c) * show,
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
