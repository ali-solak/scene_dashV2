/// The boot cover: title, a progress rule fed by the boot's
/// [ResourceGroup], and the current boot stage. Doubles as the failure
/// screen when boot throws.
library;

import 'package:flutter/material.dart';

import '../hud/ink.dart';

class LoadingScreen extends StatelessWidget {
  const LoadingScreen({super.key, this.error, this.stage, this.progress});

  final Object? error;
  final ValueNotifier<String>? stage;

  /// Fraction of the tracked loads that have settled, as handed over by
  /// `SceneView.loadingBuilder`. Null falls back to an indeterminate bar.
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final failed = error != null;
    return Center(
      child: Column(
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
          const SizedBox(height: 18),
          if (failed)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                '$error',
                textAlign: TextAlign.center,
                style: const TextStyle(color: HudInk.ash, fontSize: 12),
              ),
            )
          else
            SizedBox(width: 150, child: _ProgressRule(progress: progress)),
          const SizedBox(height: 14),
          Text(
            failed ? 'FAILED TO START' : 'LOADING',
            style: const TextStyle(
              color: HudInk.ash,
              fontSize: 11,
              letterSpacing: 4,
            ),
          ),
          if (!failed && stage != null) ...[
            const SizedBox(height: 6),
            ValueListenableBuilder<String>(
              valueListenable: stage!,
              builder: (context, value, _) => Text(
                value.toUpperCase(),
                style: const TextStyle(
                  color: HudInk.steel,
                  fontSize: 9,
                  letterSpacing: 3,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ProgressRule extends StatefulWidget {
  const _ProgressRule({required this.progress});

  final double? progress;

  @override
  State<_ProgressRule> createState() => _ProgressRuleState();
}

class _ProgressRuleState extends State<_ProgressRule> {
  double _highest = 0;

  @override
  Widget build(BuildContext context) {
    final progress = widget.progress;
    if (progress == null) {
      // Nothing to report: an indeterminate sweep still reads as "busy".
      return const LinearProgressIndicator(
        minHeight: 2,
        backgroundColor: HudInk.ruleFaint,
        color: HudInk.steel,
      );
    }
    // Keep progress from moving backwards.
    _highest = progress > _highest ? progress : _highest;
    return LinearProgressIndicator(
      value: _highest,
      minHeight: 2,
      backgroundColor: HudInk.ruleFaint,
      color: HudInk.steel,
    );
  }
}
