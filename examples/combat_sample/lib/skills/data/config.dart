part of '../skills.dart';

// --- Levelling -------------------------------------------------------------

/// How many levels deep a skill can be bought. Vitality has its own cap
/// ([maxVitalityLevel]) because it buys a flat number rather than a
/// multiplier.
const int maxSkillLevel = 5;

/// What each level past the first adds, as a fraction of the authored
/// values. The authored numbers ARE level 1, so level 5 lands at
/// 1 + 4 * this.
///
/// Applied to the numbers that make a skill FEEL heavier — damage, burn,
/// launch — and deliberately NOT to cooldowns or radii: a skill that also
/// fired more often and covered more ground would stop being a choice
/// against the other two and just become the answer.
const double skillPowerPerLevel = 0.4;

// Fire gush — a cone of flame out of the sword arm. Front-loaded damage
// plus a burn that keeps ticking after the cone is gone, so it pays off
// against a pack that is still walking in.
const double fireGushRange = 8.5;
const double fireGushHalfArc = 0.55; // ~63° wide
const double fireGushDamage = 26;
const double fireGushKnockback = 2.5;

/// The muzzle recoil: casting the gush shoves the player a little BACKWARD
/// (a decaying knockback, opposite the cone), so the blast has weight —
/// like a slight roll-back you can still walk out of.
const double fireGushRecoil = 5.5;
const double fireGushCooldownSeconds = 7;
const int fireGushCost = 30;
const int fireGushCostStep = 22;

/// Roughly chest height on the 2.6u fighter: where the flame leaves the
/// body, so the cone does not appear to erupt from the feet.
const double fireGushMuzzleHeight = 1.6;

/// The burn the gush leaves behind: damage-over-time on everything the
/// cone touched.
const double burnSeconds = 4.5;
const double burnTickSeconds = 0.5;
const double burnTickDamage = 5;

// Lava pit — thrown at the ground ahead of you and left there. No burst:
// it is area denial, and it earns its cost over its whole life.
const double lavaPitRadius = 3.4;
const double lavaPitDistance = 5.5;
const double lavaPitSeconds = 9;
const double lavaTickSeconds = 0.4;
const double lavaTickDamage = 7;
const double lavaPitCooldownSeconds = 16;
const int lavaPitCost = 60;
const int lavaPitCostStep = 40;

/// The pit's crust sits a hair above the ground so it never z-fights the
/// clearing floor.
const double lavaPitLift = 0.03;

/// Standing in lava sets you alight: the pit applies the same [Burning]
/// the gush does, refreshed on every tick, so a body in the pit carries
/// fire and keeps carrying it for a beat after it climbs out.
///
/// The TAIL is what this is for. While the victim is still standing in
/// the pit the burn never actually pays out — [lavaTickSeconds] (0.4)
/// refreshes the component before [burnTickSeconds] (0.5) can fire it, so
/// the pit's own tick stays the only damage while you are in it and the
/// fire is purely the tell. The burn starts costing the moment they
/// leave. That relationship is load-bearing: if `lavaTickSeconds` ever
/// grows past `burnTickSeconds`, the pit starts double-dipping.
const double lavaBurnSeconds = 2.2;

/// Kept under [burnTickDamage] so the tail is a consequence of the pit
/// rather than a second pit.
const double lavaBurnTickDamage = 3;

/// How long a body stays bogged after leaving the pit. The pit re-adds the
/// mire every step someone stands in it (with this `removeAfter`), so it
/// clears a short beat after they wade out — a "pulling free" tail, the
/// movement echo of the burn's fire tail.
const double lavaMireLinger = 0.35;

/// How long the pit takes to swell to full heat, and how long before it
/// closes it starts crusting over — the visual bookends of its life.
const double lavaPitOpenSeconds = 0.5;
const double lavaPitCoolSeconds = 1.5;

// Wind blast — the panic button. Barely damages; it buys room to breathe
// by throwing the whole ring off its feet and AWAY.
//
// Speed/lift are a deliberate ratio, not two independent dials. Airborne
// knockback no longer decays (see Knockback.step), so hang time is
// 2 * lift / knockbackGravity and the throw distance is speed * that.
// These give ~1.4s in the air and ~14m of travel: long enough that the
// throw is something you watch land, and far enough that they come down
// outside the fighting circle.
const double windBlastRadius = 11;
const double windBlastDamage = 12;
const double windBlastSpeed = 10;
const double windBlastLift = 12.5;
const double windBlastCooldownSeconds = 11;
const int windBlastCost = 45;
const int windBlastCostStep = 30;

// Shield — the only skill that does nothing the moment you cast it. It
// raises a barrier that then blocks BY ITSELF, and the decision you make
// is when to spend the cast, not what to point it at.
//
// Charges, not a damage pool: a block costs one charge whether it stopped
// a jab or a giant's overhead, so the shield is bought as an answer to
// BEING SURROUNDED — the situation where the hits are many and the
// individual weight of each one is beside the point.

/// Blocks the barrier stops at level 1, and what each level adds. Level 5
/// therefore lands at 7. This is the number the skill IS, so it levels
/// where the others level damage.
const int shieldBaseCharges = 3;
const int shieldChargesPerLevel = 1;

/// Long: a barrier that is up more often than it is down removes the
/// pressure the rest of the fight is built on. The cooldown starts when
/// the barrier is RAISED, so a shield that breaks early is back sooner —
/// spending it badly costs charges, not time.
const double shieldCooldownSeconds = 18;
const int shieldCost = 40;
const int shieldCostStep = 28;

/// The light sphere: big enough to read as a bubble around the fighter
/// rather than a coat of paint on it, and centred on the torso.
const double shieldRadius = 1.5;
const double shieldHeight = 1.3;

/// How long a block's flare lasts, and how long the shader's ripple takes
/// to travel the shell. Short — it is a flash of the sphere taking the
/// hit, not a state.
const double shieldFlashSeconds = 0.22;

/// Orientation for the shield hung on `handslot.l`.
///
/// NOT a yaw — that was the first guess and it did nothing, for a reason
/// worth writing down. Read out of `Knight.glb`'s bind pose, both hand
/// slots carry the same frame:
///
/// ```
/// slot local +X -> rig -X
/// slot local +Y -> rig +Z     (the sword's blade axis: it points forward)
/// slot local +Z -> rig +Y     (straight UP)
/// ```
///
/// The shield mesh is a slab in its own XY plane (bounds ±0.44 x, ±0.60 y,
/// ±0.15 z), so its FACE NORMAL is its local +Z. Mounted with an identity
/// transform that normal lands on rig +Y and the shield lies flat, face to
/// the sky, carried like a serving tray. A yaw only spins the tray.
///
/// What it needs is its face on rig +Z (KayKit characters import facing
/// +Z — see `characterModelYaw`) and its height on rig +Y, which in slot
/// space means swapping local +Y and +Z. The rotation that does it, and
/// keeps a right-handed frame by sending +X to -X, is a half turn about
/// (0, 1, 1):
///
/// ```
/// face   +Z -> slot +Y -> rig +Z   (pointing where the fighter looks)
/// height +Y -> slot +Z -> rig +Y   (upright)
/// ```
final Quaternion shieldMountRotation = Quaternion.axisAngle(
  Vector3(0, 1, 1).normalized(),
  math.pi,
);

/// Charges the barrier can hold at [maxSkillLevel], for the HUD's pips.
const int shieldMaxCharges =
    shieldBaseCharges + shieldChargesPerLevel * (maxSkillLevel - 1);

/// Blocks the barrier holds at [level] (0 when unbought).
int shieldChargesFor(int level) =>
    level <= 0 ? 0 : shieldBaseCharges + shieldChargesPerLevel * (level - 1);

// Vitality — not a cast, a purchase: every level raises the ceiling and
// gives you the difference immediately.
//
// Costs across this file are set against the payout (10 a kill, 50 a
// giant) so the first skill lands around wave 2 and the pit around wave
// 3. A sample nobody gets to SEE the lava in is a broken sample.
const double vitalityHealthPerLevel = 30;
const int vitalityBaseCost = 25;
const int vitalityCostStep = 20;
const int maxVitalityLevel = 8;

/// Each level costs more than the last, so points keep buying skills
/// rather than an unbounded health bar.
int vitalityCost(int level) => vitalityBaseCost + vitalityCostStep * level;
