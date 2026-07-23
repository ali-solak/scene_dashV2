/// The start screen. Same panel, rules and inks as the skill menu: it is
/// the same interface seen earlier, not a separate title treatment.
library;

import 'package:flutter/material.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';

import '../game/game_state.dart';
import 'ink.dart';
import 'menu_shell.dart';

/// Deliberately NOT a full-bleed scrim: the clearing is the point of this
/// screen, so the panel sits over it and lets the camera's slow orbit
/// carry the background.
class TitleMenu extends StatelessWidget {
  const TitleMenu({super.key});

  @override
  Widget build(BuildContext context) {
    return MenuShell(
      // Lighter than the other screens' scrims: the clearing stays visible.
      scrim: const Color(0x660B0C0D),
      maxWidth: 460,
      // START is pinned: in landscape the control list is taller than the
      // screen, and the button must not sit below the fold.
      footer: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: HudInk.rule)),
        ),
        padding: const EdgeInsets.fromLTRB(22, 8, 12, 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            BracketAction(
              label: 'START',
              onPressed: () => GameScope.of(context).emit(const GameStarted()),
            ),
          ],
        ),
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
                  'Defend the isle',
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
          const _ControlLine(
            keys: 'ESC',
            action: 'skill menu / button top right',
          ),
        ],
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
            // Narrow enough to leave room for the action on a phone.
            width: 96,
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
