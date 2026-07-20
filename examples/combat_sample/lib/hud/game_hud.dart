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
import 'fps.dart';
import 'ink.dart';

class GameHud extends StatelessWidget {
  const GameHud({
    super.key,
    required this.onStart,
    required this.onRestart,
    required this.onToggleMenu,
    required this.onBuySkill,
    required this.onBuyVitality,
    required this.onCast,
  });

  /// Emits [GameStarted] — leaves the title screen.
  final VoidCallback onStart;

  /// Emits [RestartRequested] (the shell owns the game handle).
  final VoidCallback onRestart;

  /// Emits [SkillMenuToggled] — opens and closes the pause.
  final VoidCallback onToggleMenu;

  /// Emits [SkillUpgradeRequested] / [VitalityRequested]. The widgets only
  /// ask; `buyUpgrades` decides whether the points are there.
  final void Function(Skill skill) onBuySkill;
  final VoidCallback onBuyVitality;

  /// Emits [SkillCast] — the skill bar's slots are BUTTONS, not just a
  /// readout. Without this there is no way to cast at all on a device
  /// with no keyboard: the number keys are the only other route in.
  final void Function(Skill skill) onCast;

  @override
  Widget build(BuildContext context) {
    // The readout sits OUTSIDE the state switch: a frame rate you can
    // only see while fighting is no use for the two screens most likely
    // to be hiding a stall (the title orbit and the death slow-mo).
    return Stack(
      fit: StackFit.expand,
      children: [
        GameStateBuilder<GameStatus>(builder: _screenFor),
        const Align(
          alignment: Alignment.topRight,
          child: SafeArea(
            child: Padding(
              padding: EdgeInsets.only(top: 18, right: 58),
              child: FpsCounter(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _screenFor(BuildContext context, GameStatus status) =>
      switch (status) {
        GameStatus.fighting => _FightHud(
            onOpenMenu: onToggleMenu,
            onCast: onCast,
          ),
        GameStatus.skillMenu => _SkillMenu(
            onClose: onToggleMenu,
            onBuySkill: onBuySkill,
            onBuyVitality: onBuyVitality,
          ),
        GameStatus.lost => _DeathPanel(onRestart: onRestart),
        GameStatus.title => _TitleMenu(onStart: onStart),
      };
}

/// The start screen. Same panel, rules and inks as the skill menu — it is
/// the same interface seen earlier, not a separate title treatment.
///
/// Deliberately NOT a full-bleed scrim: the clearing is the point of this
/// screen, so the panel sits over it and lets the camera's slow orbit
/// carry the background.
class _TitleMenu extends StatelessWidget {
  const _TitleMenu({required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0x660B0C0D),
      alignment: Alignment.center,
      child: Container(
        width: 460,
        decoration: BoxDecoration(
          color: HudInk.panel,
          border: Border.all(color: HudInk.rule),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 16),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: HudInk.rule)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'COMBAT',
                    style: TextStyle(
                      color: HudInk.bone,
                      fontSize: 30,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 12,
                      height: 1,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Hold the clearing.',
                    style: TextStyle(
                      color: HudInk.ash,
                      fontSize: 13,
                      letterSpacing: 2,
                    ),
                  ),
                ],
              ),
            ),
            const _ControlLine(keys: 'WASD', action: 'move'),
            const _ControlLine(keys: 'RMB / swipe', action: 'camera'),
            const _ControlLine(keys: 'LMB', action: 'strike · hold for heavy'),
            const _ControlLine(keys: 'SPACE', action: 'roll'),
            const _ControlLine(keys: 'TAB / MMB', action: 'lock on'),
            const _ControlLine(keys: 'Q', action: 'cycle target'),
            const _ControlLine(keys: '1-4', action: 'skills'),
            const _ControlLine(keys: 'ESC', action: 'skill menu'),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 15, 18, 17),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _BracketAction(label: 'START', onPressed: onStart),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One control, in the skill menu's ledger shape: the binding out in the
/// margin like a verse number, what it does beside it.
class _ControlLine extends StatelessWidget {
  const _ControlLine({required this.keys, required this.action});

  final String keys;
  final String action;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 9, 22, 9),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: HudInk.ruleFaint)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(
              keys,
              style: const TextStyle(
                color: HudInk.steel,
                fontSize: 12,
                letterSpacing: 1.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              action,
              style: const TextStyle(color: HudInk.ash, fontSize: 12),
            ),
          ),
        ],
      ),
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
                color: HudInk.bone,
                fontSize: 22,
                fontWeight: FontWeight.bold,
                letterSpacing: 3,
              ),
            ),
            Text(
              '$points pts',
              style: const TextStyle(
                color: HudInk.steel,
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
  const _FightHud({required this.onOpenMenu, required this.onCast});

  final VoidCallback onOpenMenu;
  final void Function(Skill skill) onCast;

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
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: _SkillBar(onCast: onCast),
            ),
          ),
          const Positioned.fill(child: IgnorePointer(child: _HurtFlash())),
        ],
      ),
    );
  }
}

/// A red bloom in from the screen edges whenever health drops.
///
/// The third leg of the hit reaction, with the fighter's flinch and the
/// camera's kick. It exists because poise means most blows do NOT stagger
/// you, and without something at the screen level the only evidence you
/// were hit was a bar moving in a corner you were not looking at.
///
/// A vignette rather than a full-screen wash: it has to be unmissable in
/// peripheral vision without covering the fight you are trying to read.
class _HurtFlash extends StatefulWidget {
  const _HurtFlash();

  @override
  State<_HurtFlash> createState() => _HurtFlashState();
}

class _HurtFlashState extends State<_HurtFlash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _flash = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  @override
  void dispose() {
    _flash.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The same trick the skill slots use for the cast pop: watch a value
    // that can only fall for one reason, rather than plumbing an event
    // from the world into the widget tree.
    return WorldBuilder<double>(
      select: (world) {
        final health =
            world.query<Health>(require: const [Player]).firstOrNull?.$2;
        if (health == null) return 1;
        return (health.current / health.max).clamp(0.0, 1.0);
      },
      builder: (context, hp) => _Flash(controller: _flash, hp: hp),
    );
  }
}

/// Split out so `didUpdateWidget` sees the previous fraction — a drop is
/// only visible by comparing frames.
class _Flash extends StatefulWidget {
  const _Flash({required this.controller, required this.hp});

  final AnimationController controller;
  final double hp;

  @override
  State<_Flash> createState() => _FlashState();
}

class _FlashState extends State<_Flash> {
  @override
  void didUpdateWidget(_Flash old) {
    super.didUpdateWidget(old);
    // Only downward. Healing between waves must not flash you red.
    if (widget.hp < old.hp) widget.controller.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final t = widget.controller.value;
        if (t == 0) return const SizedBox.shrink();
        // Punch in, ease out: the strike is instant, the ache lingers.
        final intensity = (1 - t) * (1 - t);
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              radius: 0.95,
              colors: [
                const Color(0x00E0483C),
                Color.fromRGBO(224, 72, 60, 0.62 * intensity),
              ],
              stops: const [0.55, 1],
            ),
          ),
        );
      },
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
  const _SkillBar({required this.onCast});

  final void Function(Skill skill) onCast;

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
                onCast: () => onCast(Skill.values[i]),
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
    required this.onCast,
    this.charges = 0,
  });

  final int index;
  final Skill skill;
  final int level;
  final double readiness;

  /// Tapping the slot casts it. The number keys are the desktop route in;
  /// this is the only one a touch device has.
  final VoidCallback onCast;

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
      // The slot IS the button. It was a readout before, which meant a
      // touch device could see every skill it had bought and cast none of
      // them — the number keys were the only way in.
      //
      // Opaque so the tap lands on the slot rather than falling through
      // to the scene listener underneath, which would read it as a strike.
      child: GestureDetector(
        onTap: widget.onCast,
        behavior: HitTestBehavior.opaque,
        child: _build(context),
      ),
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
            ready || holding ? HudInk.steel : HudInk.ruleFaint,
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
                        color: HudInk.steel,
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
                color: unlocked ? HudInk.bone : HudInk.ash.withValues(alpha: 0.5),
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          if (!unlocked)
            const Center(
              child: Icon(Icons.lock, size: 16, color: HudInk.ash),
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
                    color: level >= maxSkillLevel ? HudInk.jade : HudInk.steel,
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
      color: HudInk.scrim,
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
                  color: HudInk.panel,
                  border: Border.all(color: HudInk.rule),
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
        border: Border(bottom: BorderSide(color: HudInk.rule)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          const Expanded(
            child: Text(
              'SKILLS',
              style: TextStyle(
                color: HudInk.bone,
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
                  color: HudInk.steel,
                  fontSize: 26,
                  fontWeight: FontWeight.w600,
                  height: 1,
                ),
              ),
              const Text(
                'POINTS',
                style: TextStyle(
                  color: HudInk.ash,
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
            style: TextStyle(color: HudInk.ash, fontSize: 11, letterSpacing: 3),
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
        border: Border(bottom: BorderSide(color: HudInk.ruleFaint)),
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
                color: owned ? HudInk.jade : HudInk.ash,
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
                        color: HudInk.bone,
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
                          color: HudInk.jade,
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
                    color: HudInk.ash,
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
                    color: affordable ? HudInk.steel : HudInk.ash,
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
                      color: HudInk.jade,
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
                      color: HudInk.ash.withValues(alpha: 0.7),
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
            color: HudInk.steel,
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
