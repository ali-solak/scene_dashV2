/// Shared menu layout and actions.
library;

import 'package:material_ui/material_ui.dart';

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

  /// Fixed footer below [child].
  final Widget? footer;

  final Color scrim;

  /// Maximum panel width.
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

/// A bracketed text action, `[ BUY ]`. Deliberately not a filled pill:
/// a column of Material buttons would read like a settings screen.
class BracketAction extends StatelessWidget {
  const BracketAction({
    super.key,
    required this.label,
    this.onPressed,
    this.color = HudInk.steel,
    this.dense = false,
  });

  final String label;

  /// Null disables the action.
  final VoidCallback? onPressed;
  final Color color;

  /// Trims the tall touch padding for use inline in a slim ledger row (the
  /// BUY/MAX beside the price). Standalone actions (START, BACK TO THE
  /// FIGHT) stay full-size for the 48dp target.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      // 48dp minimum touch target: only the tappable area grows, not the
      // text. [dense] trades this down for the inline BUY, where the row
      // height is the constraint.
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
