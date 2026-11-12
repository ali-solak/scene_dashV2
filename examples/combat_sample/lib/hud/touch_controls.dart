/// Touch controls: a virtual joystick (movement) and attack/roll buttons.
/// Camera look stays a swipe on the open scene (the shell's Listener);
/// these widgets sit above it in the Stack, so their pointers never leak
/// into the camera. Lock-on is a tap on the scene, handled by the shell.
library;

import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';

import '../features/player/player.dart' show CombatAction;

class TouchControls extends StatelessWidget {
  const TouchControls({super.key, required this.onMove});

  /// Normalized stick position: x right, y forward (up on screen).
  final void Function(double x, double y) onMove;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            VirtualJoystick(onMove: onMove),
            const Spacer(),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _ActionButton(
                  label: 'ROLL',
                  size: 64,
                  action: CombatAction.roll,
                ),
                SizedBox(height: 16),
                _ActionButton(
                  label: 'HVY',
                  size: 64,
                  action: CombatAction.heavy,
                ),
                SizedBox(height: 16),
                _ActionButton(
                  label: 'ATK',
                  size: 90,
                  action: CombatAction.attack,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class VirtualJoystick extends StatefulWidget {
  const VirtualJoystick({super.key, required this.onMove, this.radius = 64});

  final void Function(double x, double y) onMove;
  final double radius;

  @override
  State<VirtualJoystick> createState() => _VirtualJoystickState();
}

class _VirtualJoystickState extends State<VirtualJoystick> {
  Offset _thumb = Offset.zero;

  void _update(Offset local) {
    final center = Offset(widget.radius, widget.radius);
    var delta = local - center;
    final length = delta.distance;
    if (length > widget.radius) {
      delta = delta * (widget.radius / length);
    }
    setState(() => _thumb = delta);
    // Screen up = forward.
    widget.onMove(delta.dx / widget.radius, -delta.dy / widget.radius);
  }

  void _release() {
    setState(() => _thumb = Offset.zero);
    widget.onMove(0, 0);
  }

  @override
  Widget build(BuildContext context) {
    final diameter = widget.radius * 2;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanDown: (d) => _update(d.localPosition),
      onPanUpdate: (d) => _update(d.localPosition),
      onPanEnd: (_) => _release(),
      onPanCancel: _release,
      child: SizedBox(
        width: diameter,
        height: diameter,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: diameter,
              height: diameter,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.10),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.25),
                  width: 2,
                ),
              ),
            ),
            Transform.translate(
              offset: _thumb,
              child: Container(
                width: widget.radius * 0.8,
                height: widget.radius * 0.8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.35),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.size,
    required this.action,
  });

  final String label;
  final double size;
  final CombatAction action;

  @override
  Widget build(BuildContext context) {
    return TouchAction<CombatAction>(
      action: action,
      child: _ButtonFace(label: label, size: size),
    );
  }
}

/// The shared round face every button wears.
class _ButtonFace extends StatelessWidget {
  const _ButtonFace({required this.label, required this.size});

  final String label;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: 0.12),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.3),
          width: 2,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.8),
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
          fontSize: math.max(12, size * 0.18),
        ),
      ),
    );
  }
}
