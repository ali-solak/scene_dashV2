part of '../skills.dart';

// --- Levelling -------------------------------------------------------------

/// How many levels deep a skill can be bought. Vitality has its own cap
/// ([maxVitalityLevel]) because it buys a flat number rather than a
/// multiplier.
const int maxSkillLevel = 5;

/// What each level past the first adds, as a fraction of the authored
/// (level 1) values; level 5 lands at 1 + 4 * this. Applied to damage,
/// burn, and launch, deliberately not to cooldowns or radii: a skill
/// that also fired more often would stop being a choice and just be
/// the answer.
const double skillPowerPerLevel = 0.4;

// Fire gush: a cone of flame out of the sword arm. Front-loaded damage
// plus a burn that keeps ticking after the cone is gone, so it pays off
// against a pack that is still walking in.
const double fireGushRange = 8.5;
const double fireGushHalfArc = 0.55; // ~63° wide
const double fireGushDamage = 26;
const double fireGushKnockback = 2.5;

/// Muzzle recoil: casting shoves the player backward (a decaying
/// knockback, opposite the cone) so the blast has weight, like a slight
/// roll-back you can still walk out of.
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

// Lava pit: thrown at the ground ahead of you and left there. No burst;
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

/// Standing in lava applies the gush's [Burning], refreshed every pit
/// tick, so fire lingers for a beat after climbing out. Load-bearing:
/// [lavaTickSeconds] (0.4) must stay under [burnTickSeconds] (0.5) so
/// the refresh outruns the burn tick and the pit never double-dips.
const double lavaBurnSeconds = 2.2;

/// Kept under [burnTickDamage] so the tail is a consequence of the pit
/// rather than a second pit.
const double lavaBurnTickDamage = 3;

/// How long a body stays bogged after leaving the pit. The pit re-adds
/// the mire every step (with this `removeAfter`), so it clears a short
/// beat after they wade out.
const double lavaMireLinger = 0.35;

/// How long the pit takes to swell to full heat, and how long before it
/// closes it starts crusting over: the visual bookends of its life.
const double lavaPitOpenSeconds = 0.5;
const double lavaPitCoolSeconds = 1.5;

// Wind blast: the panic button. Barely damages; it buys room by throwing
// the whole ring off its feet and away. Speed/lift are a ratio, not two
// dials: airborne knockback does not decay (see Knockback.step), so hang
// time is 2 * lift / knockbackGravity and travel is speed * that
// (~1.4s, ~14m: they come down outside the fighting circle).
const double windBlastRadius = 11;
const double windBlastDamage = 12;
const double windBlastSpeed = 10;
const double windBlastLift = 12.5;
const double windBlastCooldownSeconds = 11;
const int windBlastCost = 45;
const int windBlastCostStep = 30;

// Shield: raises a barrier that blocks by itself; the decision is when
// to cast, not what to point it at. Charges, not a damage pool: a jab
// and a giant's overhead cost one charge each, so it answers being
// surrounded rather than heavy hits.

/// Blocks the barrier stops at level 1, and what each level adds. Level 5
/// therefore lands at 7. This is the number the skill IS, so it levels
/// where the others level damage.
const int shieldBaseCharges = 3;
const int shieldChargesPerLevel = 1;

/// Long: a barrier up more often than down removes the pressure the
/// fight is built on. The cooldown starts on the raise, so a shield that
/// breaks early is back sooner; spending it badly costs charges, not time.
const double shieldCooldownSeconds = 18;
const int shieldCost = 40;
const int shieldCostStep = 28;

/// The light sphere: big enough to read as a bubble around the fighter
/// rather than a coat of paint on it, and centred on the torso.
const double shieldRadius = 1.5;
const double shieldHeight = 1.3;

/// How long a block's flare lasts, and how long the shader's ripple takes
/// to travel the shell. Short: a flash of the sphere taking the hit, not
/// a state.
const double shieldFlashSeconds = 0.22;

/// Orientation for the shield hung on `handslot.l`. Not a yaw: in
/// `Knight.glb`'s bind pose the slot maps local +Y to rig +Z (forward)
/// and local +Z to rig +Y (up), and the shield slab's face normal is its
/// local +Z, so an identity mount lays it flat like a serving tray and a
/// yaw only spins the tray. Swapping local +Y and +Z fixes it: a half
/// turn about (0, 1, 1), which keeps the frame right-handed by sending
/// +X to -X.
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

// Vitality: not a cast, a purchase; every level raises the ceiling and
// hands over the difference immediately. Costs across this file are set
// against the payout (10 a kill, 50 a giant) so the first skill lands
// around wave 2 and the pit around wave 3.
const double vitalityHealthPerLevel = 30;
const int vitalityBaseCost = 25;
const int vitalityCostStep = 20;
const int maxVitalityLevel = 8;

/// Each level costs more than the last, so points keep buying skills
/// rather than an unbounded health bar.
int vitalityCost(int level) => vitalityBaseCost + vitalityCostStep * level;
