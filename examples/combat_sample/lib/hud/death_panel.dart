/// The loss screen: `YOU DIED` over a dimmed scrim with a restart prompt.
/// Bare text on a scrim rather than the bordered panel: the run is over,
/// there is nothing to read here, only the choice to go again.
library;

import 'package:flutter/material.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';

import '../game/game_state.dart';
import 'menu_shell.dart';

class DeathPanel extends StatelessWidget {
  const DeathPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return MenuShell(
      scrim: const Color(0x88000000),
      maxWidth: 420,
      panelled: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Shrinks rather than clipping: at 52pt with this letter
          // spacing the word is ~300px, which a narrow phone does not
          // have once the shell's padding is taken out.
          const FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              'YOU DIED',
              style: TextStyle(
                color: Color(0xFFE0483C),
                fontSize: 52,
                fontWeight: FontWeight.bold,
                letterSpacing: 6,
              ),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () =>
                GameScope.of(context).emit(const RestartRequested()),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF2A2A2A),
              // Comfortably past the 48dp minimum touch target.
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 18),
            ),
            child: const Text('RESTART', style: TextStyle(letterSpacing: 2)),
          ),
        ],
      ),
    );
  }
}
