/// The in-fight overlay: the run banner, the health and heavy-charge
/// readouts, the skill bar, the skills button, and the red hurt vignette.
/// Everything here reads the world reactively (`WorldBuilder` re-selects
/// each frame, rebuilds only on change).
library;

import 'package:flutter/material.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';

import '../game/game_state.dart';
import '../game/score.dart';
import '../player/player.dart';
import '../waves/waves.dart';
import 'ink.dart';
import 'skill_bar.dart';

class FightHud extends StatelessWidget {
  const FightHud({super.key});

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
          const Align(
            alignment: Alignment.topRight,
            child: Padding(padding: EdgeInsets.all(14), child: _PauseButton()),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: const SkillBar(),
            ),
          ),
          const Positioned.fill(child: IgnorePointer(child: _HurtFlash())),
        ],
      ),
    );
  }
}

/// Opens the skill menu (pause). A cream disc in the shop panel's own
/// colours, so the button reads as the door to that screen rather than a
/// stray HUD control.
class _PauseButton extends StatelessWidget {
  const _PauseButton();

  // Matches the skill menu's cream ground and brown ink (see skill_menu.dart).
  static const Color _cream = Color(0xFFF4EFE4);
  static const Color _ink = Color(0xFF4A4034);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => GameScope.of(context).emit(const SkillMenuToggled()),
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 46,
        height: 46,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: _cream,
          boxShadow: [
            BoxShadow(
              color: Color(0x40000000),
              blurRadius: 10,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: const Icon(Icons.pause_rounded, color: _ink, size: 26),
      ),
    );
  }
}

/// (health fraction, heavy charge 0..1, heavy committed): a record, so
/// `WorldBuilder`'s `==` compare rebuilds only on real change.
typedef _HudState = (double hp, double charge, bool heavy);

_HudState _selectHud(World world) {
  final row = world
      .query2<Fighter, Health>(require: const [Player])
      .firstOrNull;
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

/// (wave, spendable points, seconds left of the breather): the run
/// readout. Shows [Score.points], not [Score.earned]; two different
/// numbers both labelled "pts" would read as a bug.
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

/// A red bloom in from the screen edges whenever health drops. Poise
/// means most blows do not stagger you, so without this the only evidence
/// of a hit was a bar in a corner. A vignette, not a full wash: it must
/// be unmissable without covering the fight.
class _HurtFlash extends StatelessWidget {
  const _HurtFlash();

  @override
  Widget build(BuildContext context) {
    // Keyed off the OUTCOME (health actually fell), not [HitLanded]: the
    // event also fires for i-framed rolls and barrier blocks, and neither
    // of those should flash you red. Only downward healing between
    // waves must not flash either.
    return WorldBuilder<double>.pulse(
      select: _playerHealth,
      trigger: (previous, next) => next < previous,
      duration: 0.42,
      pulseBuilder: (context, pulse, _) {
        if (pulse == 0) return const SizedBox.shrink();
        // Punch in, ease out: the strike is instant, the ache lingers.
        final intensity = pulse * pulse;
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

double _playerHealth(World world) {
  final health = world.query<Health>(require: const [Player]).firstOrNull?.$2;
  if (health == null) return 1;
  return (health.current / health.max).clamp(0.0, 1.0);
}
