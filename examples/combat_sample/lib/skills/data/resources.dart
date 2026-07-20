part of '../skills.dart';

/// The three castable skills. Cost and cooldown ride on the value so the
/// menu, the HUD and the cast system all read one source.
enum Skill {
  fireGush(
    label: 'FIRE GUSH',
    blurb: 'A cone of flame that leaves the pack burning.',
    cost: fireGushCost,
    costStep: fireGushCostStep,
    cooldownSeconds: fireGushCooldownSeconds,
  ),
  lavaPit(
    label: 'LAVA PIT',
    blurb: 'Opens the ground ahead. Anything standing in it cooks.',
    cost: lavaPitCost,
    costStep: lavaPitCostStep,
    cooldownSeconds: lavaPitCooldownSeconds,
  ),
  windBlast(
    label: 'WIND BLAST',
    blurb: 'Throws everything around you off its feet and away.',
    cost: windBlastCost,
    costStep: windBlastCostStep,
    cooldownSeconds: windBlastCooldownSeconds,
  ),
  shield(
    label: 'SHIELD',
    blurb: 'Raises a barrier that blocks the next few blows by itself.',
    cost: shieldCost,
    costStep: shieldCostStep,
    cooldownSeconds: shieldCooldownSeconds,
  );

  const Skill({
    required this.label,
    required this.blurb,
    required this.cost,
    required this.costStep,
    required this.cooldownSeconds,
  });

  final String label;
  final String blurb;

  /// What the FIRST level costs.
  final int cost;

  /// Added to the price for every level already owned, so a skill you
  /// keep pouring points into competes with the ones you have not
  /// touched yet.
  final int costStep;

  final double cooldownSeconds;

  /// The price of the next level when you already own [level] of them.
  int costAt(int level) => cost + costStep * level;
}

/// What the player has bought, at what level, and what is off cooldown.
/// A resource: the menu and HUD read it through a `WorldBuilder`,
/// `castSkills` mutates it.
///
/// Everything here LEVELS. A skill is not a switch you flip once — level
/// 0 is "not bought", and every level after that makes the same skill
/// heavier, on the same escalating-cost curve vitality uses. That keeps
/// late-run points meaningful once you own all three.
final class SkillBook {
  final Map<Skill, int> _levels = <Skill, int>{};
  final Map<Skill, double> _cooldowns = <Skill, double>{};

  /// Levels of the vitality upgrade bought this run.
  int vitalityLevel = 0;

  /// 0 = not bought.
  int levelOf(Skill skill) => _levels[skill] ?? 0;

  bool isUnlocked(Skill skill) => levelOf(skill) > 0;

  bool isMaxed(Skill skill) => levelOf(skill) >= maxSkillLevel;

  /// What the next level of [skill] costs.
  int priceOf(Skill skill) => skill.costAt(levelOf(skill));

  /// The multiplier this skill's numbers scale by right now. Level 1 is
  /// 1.0 (the authored values ARE level 1); each level after adds
  /// [skillPowerPerLevel]. Zero when unbought, so a stray cast that got
  /// past the gate would do nothing rather than something.
  double powerOf(Skill skill) {
    final level = levelOf(skill);
    return level <= 0 ? 0 : 1 + skillPowerPerLevel * (level - 1);
  }

  /// Seconds until [skill] can be cast again (0 = now).
  double cooldownOf(Skill skill) => _cooldowns[skill] ?? 0;

  /// 0 (just cast) → 1 (ready), for the HUD's cooldown sweep.
  double readinessOf(Skill skill) =>
      1 - (cooldownOf(skill) / skill.cooldownSeconds).clamp(0.0, 1.0);

  bool isReady(Skill skill) => isUnlocked(skill) && cooldownOf(skill) <= 0;

  /// Buys one more level.
  void upgrade(Skill skill) => _levels[skill] = levelOf(skill) + 1;

  /// Starts [skill]'s cooldown.
  void trigger(Skill skill) => _cooldowns[skill] = skill.cooldownSeconds;

  void tick(double dt) {
    for (final skill in _cooldowns.keys) {
      final remaining = _cooldowns[skill]!;
      if (remaining > 0) _cooldowns[skill] = math.max(0, remaining - dt);
    }
  }

  void reset() {
    _levels.clear();
    _cooldowns.clear();
    vitalityLevel = 0;
  }
}

/// Cast intent (the number keys / HUD buttons). Ignored unless the skill
/// is bought and off cooldown.
final class SkillCast {
  const SkillCast(this.skill);
  final Skill skill;
}

/// Menu intent: buy the next level of [skill] with banked points. The
/// first purchase unlocks it; the rest make it heavier.
final class SkillUpgradeRequested {
  const SkillUpgradeRequested(this.skill);
  final Skill skill;
}

/// Menu intent: buy one more level of vitality.
final class VitalityRequested {
  const VitalityRequested();
}
