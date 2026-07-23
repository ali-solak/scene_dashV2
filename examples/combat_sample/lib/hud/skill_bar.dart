/// The three cast slots shown along the bottom while fighting. Each slot
/// is the button for its skill (the only way in on touch), pops when the
/// skill fires, and shows its cooldown sweep, level, or live barrier
/// charges. Reads the world reactively; the list selection compares by
/// content through `WorldBuilder`'s `equals:`, so the bar rebuilds only
/// on real change.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';

import '../player/player.dart';
import '../skills/skills.dart';
import 'ink.dart';

/// Per-skill (level, readiness), plus blocks left on the barrier — the
/// shield slot shows charges instead of a cooldown sweep while it is up:
/// mid-fight you need hits left, not time until recast.
typedef _SkillSlots = ({
  List<(int level, double readiness)> slots,
  int barrierCharges,
});

_SkillSlots _selectSkills(World world) {
  final book = world.resource<SkillBook>();
  final barrier = world.query<Barrier>(require: const [Player]).firstOrNull?.$2;
  return (
    slots: [
      for (final skill in Skill.values)
        (book.levelOf(skill), book.readinessOf(skill)),
    ],
    barrierCharges: barrier?.charges ?? 0,
  );
}

/// The three cast slots. Locked slots stay visible (and greyed) so the
/// keys mean the same thing all run; a slot on cooldown fills back up.
class SkillBar extends StatelessWidget {
  const SkillBar({super.key});

  @override
  Widget build(BuildContext context) {
    return WorldBuilder<_SkillSlots>(
      select: _selectSkills,
      equals: (a, b) =>
          a.barrierCharges == b.barrierCharges && listEquals(a.slots, b.slots),
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
                onCast: () =>
                    GameScope.of(context).emit(SkillCast(Skill.values[i])),
              ),
            ),
        ],
      ),
    );
  }
}

/// One slot. The pop rides a `WorldBuilder.pulse` keyed off the CAST, not
/// the keypress: readiness falls off a cliff only when `castSkills`
/// actually triggers the skill, so a press rejected for cooldown or cost
/// never pops the slot.
class _SkillSlot extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return WorldBuilder<double>.pulse(
      select: (world) => world.resource<SkillBook>().readinessOf(skill),
      trigger: (previous, next) => previous >= 1 && next < 1,
      duration: 0.26,
      pulseBuilder: (context, pulse, _) {
        // The pulse decays 1 → 0; the pop curve wants elapsed 0 → 1.
        final t = 1 - pulse;
        final flash = math.sin(t * math.pi);
        // Snap out, ease back: a quick overshoot reads as a press. The
        // flash rides the same curve so the border and the swell are one
        // gesture rather than two.
        final swell = 1 + 0.34 * flash * (1 - t * 0.35);
        return Transform.scale(
          scale: swell,
          // The slot IS the button (touch has no number keys). Fires on
          // pointer-down via a raw Listener: a cast is a panic button, so
          // it lands the instant you touch the slot. Opaque so the jab
          // does not fall through to the strike listener beneath.
          child: Listener(
            onPointerDown: (_) => onCast(),
            behavior: HitTestBehavior.opaque,
            child: _build(context, flash),
          ),
        );
      },
    );
  }

  Widget _build(BuildContext context, double flash) {
    final unlocked = level > 0;
    final ready = unlocked && readiness >= 1;
    final holding = charges > 0;
    return Container(
      width: 54,
      height: 54,
      decoration: BoxDecoration(
        color: const Color(0xB2101214),
        // Square: the bar is a rack of slots, not a row of app icons.
        border: Border.all(
          // The border brightens with the pop. A live barrier holds the
          // accent outright: a working skill must look different from one
          // on cooldown.
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
                    for (var i = 0; i < charges; i++)
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
                color: unlocked
                    ? HudInk.bone
                    : HudInk.ash.withValues(alpha: 0.5),
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          if (!unlocked)
            const Center(child: Icon(Icons.lock, size: 16, color: HudInk.ash))
          else
            // The level, so an upgrade is visible without opening the
            // menu; the bar is where you look mid-fight.
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
