/// Shared menu chrome. [MenuShell] frames the title, skill and death
/// screens alike — the scrim, the SafeArea, and the panel with a scrolling
/// body over a pinned footer. [BracketAction] is the `[ LABEL ]` text
/// button those screens act with, deliberately not a filled pill.
library;

import 'package:flutter/material.dart';

import 'ink.dart';

class MenuShell extends StatelessWidget {
  const MenuShell({
    super.key,
    required this.child,
    this.footer,
    this.scrim = HudInk.scrim,
    this.maxWidth = 520,
    this.panelled = true,
  });

  /// The scrolling part.
  final Widget child;

  /// PINNED below [child], never scrolled away.
  ///
  /// This is what makes the menus usable in landscape. A phone on its
  /// side has roughly 320dp of usable height and the title panel wants
  /// ~440dp, so with everything in one scroll view the START button sat
  /// below the fold with nothing to suggest it was there. The action a
  /// screen exists for must not be the thing you have to discover.
  final Widget? footer;

  final Color scrim;

  /// A CEILING, not a width: the panel shrinks below this on a narrow
  /// screen instead of overflowing it.
  final double maxWidth;

  /// Draws the bordered panel. The death screen is bare text on a scrim.
  final bool panelled;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: scrim,
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: DecoratedBox(
                decoration: panelled
                    ? BoxDecoration(
                        color: HudInk.panel,
                        border: Border.all(color: HudInk.rule),
                      )
                    : const BoxDecoration(),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Flexible, not Expanded: the panel still hugs its
                    // content when there is room, and only starts
                    // scrolling once there is not.
                    Flexible(child: SingleChildScrollView(child: child)),
                    ?footer,
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A bracketed text action — `[ BUY ]`. Deliberately not a filled pill:
/// the panel is a ledger, and a column of Material buttons drags it
/// straight back to looking like a settings screen.
class BracketAction extends StatelessWidget {
  const BracketAction({
    super.key,
    required this.label,
    this.onPressed,
    this.color = HudInk.steel,
    this.dense = false,
  });

  final String label;

  /// Null renders the action disabled — it keeps its FULL size (so a row
  /// never resizes as it becomes affordable) but does not respond.
  final VoidCallback? onPressed;
  final Color color;

  /// Trims the tall touch padding for use INLINE in a slim ledger row (the
  /// BUY/MAX beside the price). The standalone actions — START, BACK TO THE
  /// FIGHT — stay full-size for the 48dp target.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      // 48dp minimum touch target for the standalone actions. The text
      // stays the same size; only the tappable area grows — on a phone a
      // 20dp-tall target is a miss waiting to happen. [dense] trades this
      // down for the inline BUY, where the row height is the constraint.
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: dense ? 8 : 15),
        child: Text(
          '[ $label ]',
          style: TextStyle(
            color: onPressed == null ? color.withValues(alpha: 0.3) : color,
            fontSize: 12,
            letterSpacing: 2,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
