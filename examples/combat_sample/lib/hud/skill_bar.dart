/// Combat skill bar.
library;

import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';

import '../features/player/player.dart' show Player;
import '../features/skills/skills.dart';
import 'ink.dart';

typedef _SlotState = ({int level, double readiness, int charges});

_SlotState _selectSlot(World world, Skill skill) {
  final book = world.resource<SkillBook>();
  final charges = skill == Skill.shield
      ? world.query<Barrier>().having<Player>().firstOrNull?.$2.charges ?? 0
      : 0;
  return (
    level: book.levelOf(skill),
    readiness: book.readinessOf(skill),
    charges: charges,
  );
}

/// Skill slots.
class SkillBar extends StatelessWidget {
  const SkillBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < Skill.values.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5),
            child: _SkillSlot(
              index: i + 1,
              skill: Skill.values[i],
              onCast: () =>
                  GameScope.of(context).emit(SkillCast(Skill.values[i])),
            ),
          ),
      ],
    );
  }
}

/// One skill slot.
class _SkillSlot extends StatelessWidget {
  const _SkillSlot({
    required this.index,
    required this.skill,
    required this.onCast,
  });

  final int index;
  final Skill skill;

  /// Tapping the slot casts it. The number keys are the desktop route in;
  /// this is the only one a touch device has.
  final VoidCallback onCast;

  @override
  Widget build(BuildContext context) {
    return WorldBuilder<_SlotState>(
      select: (world) => _selectSlot(world, skill),
      builder: (context, slot) => WorldBuilder<double>.pulse(
        select: (world) => world.resource<SkillBook>().readinessOf(skill),
        trigger: (previous, next) => previous >= 1 && next < 1,
        duration: 0.26,
        pulseBuilder: (context, pulse, _) {
          // The pulse decays 1 → 0; the pop curve wants elapsed 0 → 1.
          final t = 1 - pulse;
          final flash = math.sin(t * math.pi);
          // Press animation.
          final swell = 1 + 0.34 * flash * (1 - t * 0.35);
          return Transform.scale(
            scale: swell,
            // Cast on touch down.
            child: Listener(
              onPointerDown: (_) => onCast(),
              behavior: HitTestBehavior.opaque,
              child: _SlotFace(
                index: index,
                level: slot.level,
                readiness: slot.readiness,
                charges: slot.charges,
                flash: flash,
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Skill slot contents.
class _SlotFace extends StatelessWidget {
  const _SlotFace({
    required this.index,
    required this.level,
    required this.readiness,
    required this.charges,
    required this.flash,
  });

  final int index;
  final int level;
  final double readiness;
  final int charges;

  /// 0 at rest, 1 at the top of the cast pop.
  final double flash;

  @override
  Widget build(BuildContext context) {
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
          // Skill state border.
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
            // Skill level.
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
