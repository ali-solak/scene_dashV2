/// The flat HUD: the run banner, health and heavy-charge readouts and the
/// skill bar while fighting; the skill menu while it is open; a death
/// panel with a restart prompt while lost. Reads the world reactively
/// (`WorldBuilder` re-selects each frame, rebuilds only on change);
/// `GameStateBuilder` routes on the run state.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart' show immutable, listEquals;
import 'package:flutter/material.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';

import '../game/game_state.dart';
import '../game/score.dart';
import '../player/player.dart';
import '../skills/skills.dart';
import '../waves/waves.dart';

/// One palette, so the HUD reads as a set rather than as whatever colour
/// each widget reached for. Cold steel against the world's greens and the
/// fight's reds: the UI stays legible over grass, fire and blood without
/// competing with any of them.
abstract final class _Ink {
  static const scrim = Color(0xE60B0C0D);
  static const panel = Color(0xFF141618);

  /// Text: bone for what matters, ash for what supports it.
  static const bone = Color(0xFFE8E3D9);
  static const ash = Color(0xFF8F8A80);

  /// Live/affordable/ready. The one accent.
  static const steel = Color(0xFF8FB6C6);

  /// Already yours.
  static const jade = Color(0xFF7E9E7A);

  /// Hairlines and frames.
  static const rule = Color(0x33E8E3D9);
  static const ruleFaint = Color(0x18E8E3D9);
}

class GameHud extends StatelessWidget {
  const GameHud({
    super.key,
    required this.onRestart,
    required this.onToggleMenu,
    required this.onBuySkill,
    required this.onBuyVitality,
  });

  /// Emits [RestartRequested] (the shell owns the game handle).
  final VoidCallback onRestart;

  /// Emits [SkillMenuToggled] — opens and closes the pause.
  final VoidCallback onToggleMenu;

  /// Emits [SkillUpgradeRequested] / [VitalityRequested]. The widgets only
  /// ask; `buyUpgrades` decides whether the points are there.
  final void Function(Skill skill) onBuySkill;
  final VoidCallback onBuyVitality;

  @override
  Widget build(BuildContext context) {
    return GameStateBuilder<GameStatus>(
      builder: (context, status) => switch (status) {
        GameStatus.fighting => _FightHud(onOpenMenu: onToggleMenu),
        GameStatus.skillMenu => _SkillMenu(
            onClose: onToggleMenu,
            onBuySkill: onBuySkill,
            onBuyVitality: onBuyVitality,
          ),
        GameStatus.lost => _DeathPanel(onRestart: onRestart),
      },
    );
  }
}

/// (health fraction, heavy-charge 0–1, heavy committed) — a record, so
/// `WorldBuilder`'s `==` compare rebuilds only on real change.
typedef _HudState = (double hp, double charge, bool heavy);

_HudState _selectHud(World world) {
  final row =
      world.query2<Fighter, Health>(require: const [Player]).firstOrNull;
  if (row == null) return (1, 0, false);
  final (_, fighter, health) = row;
  final hp = (health.current / health.max).clamp(0.0, 1.0);
  var charge = 0.0;
  if (fighter.phase.state == CombatPhase.startup) {
    charge = (fighter.phase.elapsed / heavyThresholdSeconds).clamp(0.0, 1.0);
  } else if (fighter.heavy) {
    charge = 1;
  }
  return (hp, charge, fighter.heavy);
}

/// (wave, spendable points, seconds left of the breather) — the run
/// readout.
///
/// Shows [Score.points] (what you can spend), NOT [Score.earned] (the
/// lifetime total). Two different numbers both labelled "pts" — one here
/// and one in the menu — just reads as a bug.
typedef _RunState = (int wave, int points, int breather);

_RunState _selectRun(World world) {
  final waves = world.resource<WaveState>();
  final score = world.resource<Score>();
  return (waves.wave, score.points, waves.intermission.ceil());
}

class _RunBanner extends StatelessWidget {
  const _RunBanner();

  @override
  Widget build(BuildContext context) {
    return WorldBuilder<_RunState>(
      select: _selectRun,
      builder: (context, state) {
        final (wave, points, breather) = state;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              breather > 0 ? 'WAVE ${wave + 1} IN $breather' : 'WAVE $wave',
              style: const TextStyle(
                color: _Ink.bone,
                fontSize: 22,
                fontWeight: FontWeight.bold,
                letterSpacing: 3,
              ),
            ),
            Text(
              '$points pts',
              style: const TextStyle(
                color: _Ink.steel,
                fontSize: 16,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 10),
          ],
        );
      },
    );
  }
}

class _FightHud extends StatelessWidget {
  const _FightHud({required this.onOpenMenu});

  final VoidCallback onOpenMenu;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Stack(
        children: [
          Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: WorldBuilder<_HudState>(
                select: _selectHud,
                builder: (context, state) {
                  final (hp, charge, heavy) = state;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const _RunBanner(),
                      _Bar(
                        value: hp,
                        width: 220,
                        color: const Color(0xFFE0483C),
                        background: const Color(0x66401010),
                      ),
                      const SizedBox(height: 8),
                      if (charge > 0)
                        _Bar(
                          value: charge,
                          width: 160,
                          height: 8,
                          color: heavy
                              ? const Color(0xFFE07A2B)
                              : const Color(0xFF9C6A3C),
                          background: const Color(0x66302010),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
          Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: IconButton(
                onPressed: onOpenMenu,
                icon: const Icon(Icons.auto_awesome),
                color: Colors.white70,
                tooltip: 'Skills (Esc)',
              ),
            ),
          ),
          const Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: EdgeInsets.only(bottom: 20),
              child: _SkillBar(),
            ),
          ),
        ],
      ),
    );
  }
}

/// The three cast slots. Locked slots stay visible (and greyed) so the
/// keys mean the same thing all run; a slot on cooldown fills back up.
///
/// `WorldBuilder` re-selects every frame and rebuilds on `!=`, so a
/// selection has to be a VALUE — a bare `List` would compare by identity
/// and rebuild the bar every single frame.
@immutable
final class _SkillSlots {
  const _SkillSlots(this.slots, this.barrierCharges);

  final List<(int level, double readiness)> slots;

  /// Blocks left on the barrier right now, 0 when it is down. The shield
  /// slot shows this instead of a cooldown sweep while it is up — what
  /// you need mid-fight is how many hits you have left, not how long
  /// until you could raise another one you cannot raise yet anyway.
  final int barrierCharges;

  @override
  bool operator ==(Object other) =>
      other is _SkillSlots &&
      barrierCharges == other.barrierCharges &&
      listEquals(slots, other.slots);

  @override
  int get hashCode => Object.hash(Object.hashAll(slots), barrierCharges);
}

_SkillSlots _selectSkills(World world) {
  final book = world.resource<SkillBook>();
  final barrier =
      world.query<Barrier>(require: const [Player]).firstOrNull?.$2;
  return _SkillSlots([
    for (final skill in Skill.values)
      (book.levelOf(skill), book.readinessOf(skill)),
  ], barrier?.charges ?? 0);
}

class _SkillBar extends StatelessWidget {
  const _SkillBar();

  @override
  Widget build(BuildContext context) {
    return WorldBuilder<_SkillSlots>(
      select: _selectSkills,
      builder: (context, state) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < state.slots.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              child: _SkillSlot(
                index: i + 1,
                skill: Skill.values[i],
                level: state.slots[i].$1,
                readiness: state.slots[i].$2,
                charges: Skill.values[i] == Skill.shield
                    ? state.barrierCharges
                    : 0,
              ),
            ),
        ],
      ),
    );
  }
}

/// One slot. Stateful only so it can POP when the skill fires.
///
/// The cast itself is invisible on the HUD otherwise: the cooldown sweep
/// starts draining, which is information but not feedback. The pop is the
/// widget acknowledging the keypress on the frame it happened, which is
/// what makes a button feel connected to the thing it does.
class _SkillSlot extends StatefulWidget {
  const _SkillSlot({
    required this.index,
    required this.skill,
    required this.level,
    required this.readiness,
    this.charges = 0,
  });

  final int index;
  final Skill skill;
  final int level;
  final double readiness;

  /// Live charges on a skill that holds some (the shield's barrier);
  /// 0 for everything else, and for a barrier that is down.
  final int charges;

  @override
  State<_SkillSlot> createState() => _SkillSlotState();
}

class _SkillSlotState extends State<_SkillSlot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );

  @override
  void dispose() {
    _pop.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(_SkillSlot old) {
    super.didUpdateWidget(old);
    // A cast is the one moment readiness falls off a cliff: it can only
    // go DOWN by being spent, and it climbs back gradually. Watching the
    // readiness itself means no extra event plumbing between the world
    // and the widget — the state the HUD already reads says it.
    if (old.readiness >= 1 && widget.readiness < 1) {
      _pop.forward(from: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pop,
      builder: (context, child) {
        final t = _pop.value;
        // Snap out, ease back: a quick overshoot reads as a press. The
        // flash rides the same curve so the border and the swell are one
        // gesture rather than two.
        final swell = 1 + 0.34 * math.sin(t * math.pi) * (1 - t * 0.35);
        return Transform.scale(scale: swell, child: child);
      },
      child: _build(context),
    );
  }

  Widget _build(BuildContext context) {
    final index = widget.index;
    final level = widget.level;
    final readiness = widget.readiness;
    final unlocked = level > 0;
    final ready = unlocked && readiness >= 1;
    final holding = widget.charges > 0;
    final flash = math.sin(_pop.value * math.pi);
    return Container(
      width: 54,
      height: 54,
      decoration: BoxDecoration(
        color: const Color(0xB2101214),
        // Square: the bar is a rack of slots, not a row of app icons.
        border: Border.all(
          // The border brightens with the pop, so a slot that just fired
          // still reads as "yours" for the beat after the cooldown greys
          // it out. A live barrier holds the accent outright: the skill
          // is not "ready", it is WORKING, and that has to look different
          // from a slot on cooldown.
          color: Color.lerp(
            ready || holding ? _Ink.steel : _Ink.ruleFaint,
            Colors.white,
            flash,
          )!,
          width: ready || holding || flash > 0.2 ? 2 : 1,
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // A live barrier replaces the cooldown sweep: the sweep would
          // say "not yet" about a skill that is currently doing its job.
          if (holding)
            Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < widget.charges; i++)
                      Container(
                        width: 5,
                        height: 5,
                        margin: const EdgeInsets.symmetric(horizontal: 1.5),
                        color: _Ink.steel,
                      ),
                  ],
                ),
              ),
            )
          // The cooldown sweep: fills from the bottom as it comes back.
          else if (unlocked && readiness < 1)
            Align(
              alignment: Alignment.bottomCenter,
              child: FractionallySizedBox(
                heightFactor: readiness.clamp(0.0, 1.0),
                child: Container(color: const Color(0x338FB6C6)),
              ),
            ),
          Center(
            child: Text(
              '$index',
              style: TextStyle(
                color: unlocked ? _Ink.bone : _Ink.ash.withValues(alpha: 0.5),
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          if (!unlocked)
            const Center(
              child: Icon(Icons.lock, size: 16, color: _Ink.ash),
            )
          else
            // The level, so an upgrade is visible without opening the
            // menu — the bar is where you look mid-fight.
            Align(
              alignment: Alignment.bottomRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 4, bottom: 2),
                child: Text(
                  '$level',
                  style: TextStyle(
                    color: level >= maxSkillLevel ? _Ink.jade : _Ink.steel,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Points, vitality level and what is already owned — everything the menu
/// needs to decide what is affordable. A value type, for the same reason
/// [_SkillSlots] is one.
@immutable
final class _MenuState {
  const _MenuState(this.points, this.vitality, this.levels);

  final int points;
  final int vitality;

  /// Level per skill, in `Skill.values` order. 0 = not bought.
  final List<int> levels;

  @override
  bool operator ==(Object other) =>
      other is _MenuState &&
      points == other.points &&
      vitality == other.vitality &&
      listEquals(levels, other.levels);

  @override
  int get hashCode => Object.hash(points, vitality, Object.hashAll(levels));
}

_MenuState _selectMenu(World world) {
  final book = world.resource<SkillBook>();
  return _MenuState(
    world.resource<Score>().points,
    book.vitalityLevel,
    [for (final skill in Skill.values) book.levelOf(skill)],
  );
}

/// The pause screen: spend what the run has earned. The world is frozen
/// behind it — the menu is a [GameStatus], not an overlay with a flag.
class _SkillMenu extends StatelessWidget {
  const _SkillMenu({
    required this.onClose,
    required this.onBuySkill,
    required this.onBuyVitality,
  });

  final VoidCallback onClose;
  final void Function(Skill skill) onBuySkill;
  final VoidCallback onBuyVitality;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _Ink.scrim,
      alignment: Alignment.center,
      child: WorldBuilder<_MenuState>(
        select: _selectMenu,
        builder: (context, state) {
          final points = state.points;
          final vitality = state.vitality;
          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Center(
              child: Container(
                width: 520,
                decoration: BoxDecoration(
                  color: _Ink.panel,
                  border: Border.all(color: _Ink.rule),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _MenuHeader(points: points),
                    for (var i = 0; i < Skill.values.length; i++)
                      _MenuRow(
                        slot: '${i + 1}',
                        title: Skill.values[i].label,
                        rank: state.levels[i],
                        blurb: Skill.values[i].blurb,
                        cost: Skill.values[i].costAt(state.levels[i]),
                        owned: state.levels[i] >= maxSkillLevel,
                        ownedLabel: 'MAX',
                        points: points,
                        onBuy: () => onBuySkill(Skill.values[i]),
                      ),
                    _MenuRow(
                      slot: '+',
                      title: 'VITALITY',
                      rank: vitality,
                      blurb: 'Raises your health by '
                          '${vitalityHealthPerLevel.toStringAsFixed(0)} '
                          'and heals you for it now.',
                      cost: vitalityCost(vitality),
                      owned: vitality >= maxVitalityLevel,
                      ownedLabel: 'MAX',
                      points: points,
                      onBuy: onBuyVitality,
                    ),
                    _MenuFooter(onClose: onClose),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Title on the left, the purse on the right, one rule under both.
class _MenuHeader extends StatelessWidget {
  const _MenuHeader({required this.points});

  final int points;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 15),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _Ink.rule)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          const Expanded(
            child: Text(
              'SKILLS',
              style: TextStyle(
                color: _Ink.bone,
                fontSize: 26,
                fontWeight: FontWeight.w600,
                letterSpacing: 10,
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$points',
                style: const TextStyle(
                  color: _Ink.steel,
                  fontSize: 26,
                  fontWeight: FontWeight.w600,
                  height: 1,
                ),
              ),
              const Text(
                'POINTS',
                style: TextStyle(
                  color: _Ink.ash,
                  fontSize: 10,
                  letterSpacing: 3,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MenuFooter extends StatelessWidget {
  const _MenuFooter({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 13, 18, 15),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'ESC',
            style: TextStyle(color: _Ink.ash, fontSize: 11, letterSpacing: 3),
          ),
          _BracketAction(label: 'BACK TO THE FIGHT', onPressed: onClose),
        ],
      ),
    );
  }
}

/// One ledger line. The price column is ALWAYS populated — owned entries
/// still show what they cost, and unaffordable ones show the shortfall —
/// so the menu answers "what am I saving for" without being poked at.
class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.slot,
    required this.title,
    required this.blurb,
    required this.cost,
    required this.owned,
    required this.points,
    required this.onBuy,
    this.rank = 0,
    this.ownedLabel = 'OWNED',
  });

  final String slot;
  final String title;
  final String blurb;
  final int cost;
  final bool owned;
  final int rank;
  final String ownedLabel;
  final int points;
  final VoidCallback onBuy;

  @override
  Widget build(BuildContext context) {
    final affordable = !owned && points >= cost;
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 15, 22, 15),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _Ink.ruleFaint)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The keybind, out in the margin like a verse number.
          SizedBox(
            width: 24,
            child: Text(
              slot,
              style: TextStyle(
                color: owned ? _Ink.jade : _Ink.ash,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: _Ink.bone,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 3,
                      ),
                    ),
                    if (rank > 0) ...[
                      const SizedBox(width: 9),
                      Text(
                        'I' * rank,
                        style: const TextStyle(
                          color: _Ink.jade,
                          fontSize: 13,
                          letterSpacing: 2,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  blurb,
                  style: const TextStyle(
                    color: _Ink.ash,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          SizedBox(
            width: 112,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$cost PTS',
                  style: TextStyle(
                    color: affordable ? _Ink.steel : _Ink.ash,
                    fontSize: 13,
                    letterSpacing: 1.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                if (owned)
                  Text(
                    ownedLabel,
                    style: const TextStyle(
                      color: _Ink.jade,
                      fontSize: 11,
                      letterSpacing: 2,
                    ),
                  )
                else if (affordable)
                  _BracketAction(label: 'BUY', onPressed: onBuy)
                else
                  Text(
                    '${cost - points} SHORT',
                    style: TextStyle(
                      color: _Ink.ash.withValues(alpha: 0.7),
                      fontSize: 11,
                      letterSpacing: 1.5,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A bracketed text action — `[ BUY ]`. Deliberately not a filled pill:
/// the panel is a ledger, and a column of Material buttons drags it
/// straight back to looking like a settings screen.
class _BracketAction extends StatelessWidget {
  const _BracketAction({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        child: Text(
          '[ $label ]',
          style: const TextStyle(
            color: _Ink.steel,
            fontSize: 12,
            letterSpacing: 2,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.value,
    required this.width,
    required this.color,
    required this.background,
    this.height = 16,
  });

  final double value;
  final double width;
  final double height;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(height / 2),
        border: Border.all(color: Colors.white24),
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: value.clamp(0.0, 1.0),
          child: Container(
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(height / 2),
            ),
          ),
        ),
      ),
    );
  }
}

class _DeathPanel extends StatelessWidget {
  const _DeathPanel({required this.onRestart});

  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0x88000000),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'YOU DIED',
            style: TextStyle(
              color: Color(0xFFE0483C),
              fontSize: 52,
              fontWeight: FontWeight.bold,
              letterSpacing: 6,
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: onRestart,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF2A2A2A),
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            ),
            child: const Text('RESTART', style: TextStyle(letterSpacing: 2)),
          ),
        ],
      ),
    );
  }
}
