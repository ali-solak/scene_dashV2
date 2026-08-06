part of '../skills.dart';

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

  final int cost;
  final int costStep;

  final double cooldownSeconds;

  int costAt(int level) => cost + costStep * level;
}

final class SkillBook {
  final Map<Skill, int> _levels = <Skill, int>{};
  final Map<Skill, double> _cooldowns = <Skill, double>{};

  int vitalityLevel = 0;
  int levelOf(Skill skill) => _levels[skill] ?? 0;

  bool isUnlocked(Skill skill) => levelOf(skill) > 0;

  bool isMaxed(Skill skill) => levelOf(skill) >= maxSkillLevel;

  int priceOf(Skill skill) => skill.costAt(levelOf(skill));
  double powerOf(Skill skill) {
    final level = levelOf(skill);
    return level <= 0 ? 0 : 1 + skillPowerPerLevel * (level - 1);
  }

  double cooldownOf(Skill skill) => _cooldowns[skill] ?? 0;
  double readinessOf(Skill skill) =>
      1 - (cooldownOf(skill) / skill.cooldownSeconds).clamp(0.0, 1.0);

  bool isReady(Skill skill) => isUnlocked(skill) && cooldownOf(skill) <= 0;

  void upgrade(Skill skill) => _levels[skill] = levelOf(skill) + 1;
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

final class SkillCast {
  const SkillCast(this.skill);
  final Skill skill;
}

final class SkillUpgradeRequested {
  const SkillUpgradeRequested(this.skill);
  final Skill skill;
}

final class VitalityRequested {
  const VitalityRequested();
}
