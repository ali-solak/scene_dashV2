/// The boot cover: title, a thin progress rule, and the current boot
/// stage. Doubles as the failure screen when boot throws.
library;

import 'package:flutter/material.dart';

import 'ink.dart';

class LoadingScreen extends StatelessWidget {
  const LoadingScreen({super.key, this.error, this.stage});

  final Object? error;
  final ValueNotifier<String>? stage;

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
            SizedBox(
              width: 150,
              child: LinearProgressIndicator(
                minHeight: 2,
                backgroundColor: HudInk.ruleFaint,
                color: HudInk.steel,
              ),
            ),
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
