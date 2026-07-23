/// The three cast slots shown along the bottom while fighting. Each slot
/// is the button for its skill (the only way in on touch), pops when the
/// skill fires, and shows its cooldown sweep, level, or live barrier
/// charges. Reads the world reactively; a selection is a value type so
/// `WorldBuilder` rebuilds only on real change.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart' show immutable, listEquals;
import 'package:flutter/material.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';

import '../player/player.dart';
import '../skills/skills.dart';
import 'ink.dart';

/// `WorldBuilder` re-selects every frame and rebuilds on `!=`, so a
/// selection has to be a value; a bare `List` would compare by identity
/// and rebuild the bar every single frame.
@immutable
final class _SkillSlots {
  const _SkillSlots(this.slots, this.barrierCharges);

  final List<(int level, double readiness)> slots;

  /// Blocks left on the barrier, 0 when it is down. The shield slot shows
  /// this instead of a cooldown sweep while it is up: mid-fight you need
  /// hits left, not time until recast.
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
  final barrier = world.query<Barrier>(require: const [Player]).firstOrNull?.$2;
  return _SkillSlots([
    for (final skill in Skill.values)
      (book.levelOf(skill), book.readinessOf(skill)),
  ], barrier?.charges ?? 0);
}

/// The three cast slots. Locked slots stay visible (and greyed) so the
/// keys mean the same thing all run; a slot on cooldown fills back up.
class SkillBar extends StatelessWidget {
  const SkillBar({super.key});

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
                onCast: () =>
                    GameScope.of(context).emit(SkillCast(Skill.values[i])),
              ),
            ),
        ],
      ),
    );
  }
}

/// One slot. Stateful only so it can pop when the skill fires: the pop
/// acknowledges the keypress on the frame it happened, which is what
/// makes the button feel connected to the cast.
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
    // A cast is the one moment readiness falls off a cliff, so watching
    // it needs no event plumbing between the world and the widget.
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
      // The slot IS the button (touch has no number keys). Fires on
      // pointer-down via a raw Listener: a cast is a panic button, so it
      // lands the instant you touch the slot. Opaque so the jab does not
      // fall through to the strike listener beneath.
      child: Listener(
        onPointerDown: (_) => widget.onCast(),
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
