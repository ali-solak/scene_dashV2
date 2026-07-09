import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';

import '../collectables/collectables.dart';
import '../game/game_state.dart';
import '../projectiles/projectiles.dart';
import 'debug_panel.dart';

/// Plain Flutter HUD over the scene, built from the widget layer:
/// [GameStateBuilder] routes playing/lost on state transitions, and each
/// section is its own [WorldBuilder] selecting exactly what it renders —
/// quantised values with meaningful `==`, so a section rebuilds only when
/// something visible changed. Everything reads *through the world*; no
/// game object is constructed in `main` and threaded here. Touch intent
/// flows back through callbacks — widgets never mutate components.
class GameHud extends StatelessWidget {
  const GameHud({
    super.key,
    required this.onLeftChanged,
    required this.onRightChanged,
    required this.onFireChanged,
    required this.onFireCanceled,
    required this.onRestart,
  });

  final ValueChanged<bool> onLeftChanged;
  final ValueChanged<bool> onRightChanged;
  final ValueChanged<bool> onFireChanged;
  final VoidCallback onFireCanceled;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    return GameStateBuilder<GameStatus>(
      builder: (context, status) => switch (status) {
        GameStatus.playing => _PlayingHud(
          onLeftChanged: onLeftChanged,
          onRightChanged: onRightChanged,
          onFireChanged: onFireChanged,
          onFireCanceled: onFireCanceled,
        ),
        GameStatus.lost => _GameOverPanel(onRestart: onRestart),
      },
    );
  }
}

/// Quantised to whole percent so a section only rebuilds on a visible step.
double _centi(double v) => (v.clamp(0.0, 1.0) * 100).round() / 100;

Widget _shadowed(String text, {required double fontSize}) {
  return Text(
    text,
    textAlign: TextAlign.center,
    style: TextStyle(
      color: Colors.white,
      fontSize: fontSize,
      fontWeight: FontWeight.w600,
      shadows: const [
        Shadow(blurRadius: 4, color: Colors.black, offset: Offset(0, 1)),
      ],
    ),
  );
}

class _PlayingHud extends StatelessWidget {
  const _PlayingHud({
    required this.onLeftChanged,
    required this.onRightChanged,
    required this.onFireChanged,
    required this.onFireCanceled,
  });

  final ValueChanged<bool> onLeftChanged;
  final ValueChanged<bool> onRightChanged;
  final ValueChanged<bool> onFireChanged;
  final VoidCallback onFireCanceled;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned(
          top: 24,
          left: 24,
          child: IgnorePointer(
            child: WorldBuilder<int>(
              select: (world) => world.resource<GameState>().survivedTenths,
              builder: (context, tenths) => _shadowed(
                'Survived: ${(tenths / 10).toStringAsFixed(1)}s',
                fontSize: 22,
              ),
            ),
          ),
        ),
        Positioned(
          top: 24,
          right: 24,
          child: IgnorePointer(
            child: WorldBuilder<int>(
              select: (world) => world.resource<FpsCounter>().fps,
              builder: (context, fps) => _shadowed('FPS: $fps', fontSize: 18),
            ),
          ),
        ),
        Positioned(
          top: 60,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: WorldBuilder<(bool, double, bool)>(
              select: (world) {
                final shield = world.resource<ShieldState>();
                return (
                  shield.active,
                  _centi(shield.normalized),
                  shield.expiringSoon,
                );
              },
              builder: (context, shield) => shield.$1
                  ? _ShieldBadge(normalized: shield.$2, expiring: shield.$3)
                  : const SizedBox.shrink(),
            ),
          ),
        ),
        const Positioned(top: 64, left: 24, child: DebugPanel()),
        _Controls(
          onLeftChanged: onLeftChanged,
          onRightChanged: onRightChanged,
          onFireChanged: onFireChanged,
          onFireCanceled: onFireCanceled,
        ),
      ],
    );
  }
}

/// Movement grouped bottom-left; a large fire control bottom-right.
class _Controls extends StatelessWidget {
  const _Controls({
    required this.onLeftChanged,
    required this.onRightChanged,
    required this.onFireChanged,
    required this.onFireCanceled,
  });

  final ValueChanged<bool> onLeftChanged;
  final ValueChanged<bool> onRightChanged;
  final ValueChanged<bool> onFireChanged;
  final VoidCallback onFireCanceled;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Stack(
        children: [
          Align(
            alignment: Alignment.bottomLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _HoldButton(
                  icon: Icons.arrow_left_rounded,
                  semanticLabel: 'Move left',
                  onChanged: onLeftChanged,
                ),
                const SizedBox(width: 16),
                _HoldButton(
                  icon: Icons.arrow_right_rounded,
                  semanticLabel: 'Move right',
                  onChanged: onRightChanged,
                ),
              ],
            ),
          ),
          Align(
            alignment: Alignment.bottomRight,
            // The ring and cooldown meter read the blaster straight off the
            // world; the fire button's pressed visuals stay widget state.
            child: WorldBuilder<(double, double, bool, bool)>(
              select: (world) {
                final blaster = world.resource<Blaster>();
                return (
                  _centi(blaster.charge01),
                  _centi(blaster.cooldown01),
                  blaster.isCharging,
                  blaster.isReady,
                );
              },
              builder: (context, b) => _FireControl(
                charge01: b.$1,
                cooldown01: b.$2,
                charging: b.$3,
                ready: b.$4,
                onChanged: onFireChanged,
                onCanceled: onFireCanceled,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HoldButton extends StatefulWidget {
  const _HoldButton({
    required this.icon,
    required this.semanticLabel,
    required this.onChanged,
  });

  final IconData icon;
  final String semanticLabel;
  final ValueChanged<bool> onChanged;

  @override
  State<_HoldButton> createState() => _HoldButtonState();
}

class _HoldButtonState extends State<_HoldButton> {
  bool _held = false;

  void _setHeld(bool value) {
    if (_held == value) return;
    setState(() => _held = value);
    widget.onChanged(value);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: widget.semanticLabel,
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _setHeld(true),
        onTapUp: (_) => _setHeld(false),
        onTapCancel: () => _setHeld(false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 90),
          width: 92,
          height: 92,
          decoration: BoxDecoration(
            color: _held ? Colors.white30 : Colors.black38,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white54, width: 1.5),
            boxShadow: const [
              BoxShadow(
                color: Colors.black45,
                blurRadius: 12,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Icon(widget.icon, color: Colors.white, size: 54),
        ),
      ),
    );
  }
}

/// Hold-capable fire control. A press starts holding; release fires (burst
/// or charged, decided by the ECS blaster); `onTapCancel` cancels rather
/// than fires. The ring shows live charge while held and cooldown recovery
/// while cooling, both from the quantised world selection — never the
/// mutable Blaster.
class _FireControl extends StatefulWidget {
  const _FireControl({
    required this.charge01,
    required this.cooldown01,
    required this.charging,
    required this.ready,
    required this.onChanged,
    required this.onCanceled,
  });

  final double charge01;
  final double cooldown01;
  final bool charging;
  final bool ready;
  final ValueChanged<bool> onChanged;
  final VoidCallback onCanceled;

  @override
  State<_FireControl> createState() => _FireControlState();
}

class _FireControlState extends State<_FireControl> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  String get _semanticLabel {
    if (widget.charging) {
      return 'Charging ${(widget.charge01 * 100).round()} percent';
    }
    if (widget.cooldown01 > 0 && !widget.ready) {
      return 'Blaster cooling down';
    }
    return 'Blaster ready';
  }

  @override
  Widget build(BuildContext context) {
    final cooling = widget.cooldown01 > 0 && !widget.charging;
    final fullCharge = widget.charging && widget.charge01 >= 0.999;

    // The ring shows charge while held and a faint ready ring otherwise;
    // the cooldown is shown separately as a vertical recovery meter above
    // the button.
    final double ringProgress;
    final Color ringColor;
    if (widget.charging) {
      ringProgress = widget.charge01;
      ringColor = fullCharge
          ? const Color(0xFFFFE16A)
          : const Color(0xFF53E6FF);
    } else {
      ringProgress = 1;
      ringColor = const Color(0x5553E6FF);
    }

    final dim = cooling && !_pressed;
    final fireButton = Semantics(
      label: _semanticLabel,
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) {
          _setPressed(true);
          widget.onChanged(true);
        },
        onTapUp: (_) {
          _setPressed(false);
          widget.onChanged(false);
        },
        onTapCancel: () {
          _setPressed(false);
          widget.onCanceled();
        },
        child: SizedBox(
          width: 116,
          height: 116,
          child: CustomPaint(
            painter: _FireRingPainter(
              progress: ringProgress.clamp(0.0, 1.0),
              color: ringColor,
              glow: fullCharge,
            ),
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 90),
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  color: _pressed
                      ? Colors.white30
                      : (dim ? Colors.black54 : Colors.black38),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: fullCharge
                        ? const Color(0xFFFFE16A)
                        : Colors.white54,
                    width: fullCharge ? 2.5 : 1.5,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black45,
                      blurRadius: 12,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.bolt_rounded,
                  color: dim ? Colors.white54 : Colors.white,
                  size: 46,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          height: 54,
          width: 18,
          child: cooling ? _CooldownBar(recovery: 1 - widget.cooldown01) : null,
        ),
        const SizedBox(height: 6),
        fireButton,
      ],
    );
  }
}

/// A vertical recovery meter shown above the fire button while the blaster
/// cools down: empty right after firing, full when the blaster is ready
/// again.
class _CooldownBar extends StatelessWidget {
  const _CooldownBar({required this.recovery});

  /// 0..1 recovery progress (0 just after firing, 1 when ready).
  final double recovery;

  @override
  Widget build(BuildContext context) {
    final r = recovery.clamp(0.0, 1.0);
    final color = Color.lerp(
      const Color(0xFFFFB36A),
      const Color(0xFF6FE0FF),
      r,
    )!;
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        width: 10,
        decoration: BoxDecoration(
          color: Colors.black45,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: Colors.white24),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: FractionallySizedBox(
              heightFactor: r,
              child: Container(color: color),
            ),
          ),
        ),
      ),
    );
  }
}

class _FireRingPainter extends CustomPainter {
  _FireRingPainter({
    required this.progress,
    required this.color,
    required this.glow,
  });

  final double progress;
  final Color color;
  final bool glow;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 5;
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..color = Colors.white24;
    canvas.drawCircle(center, radius, track);

    if (progress <= 0) return;
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = glow ? 7 : 5
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      progress * 2 * math.pi,
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(covariant _FireRingPainter old) =>
      old.progress != progress || old.color != color || old.glow != glow;
}

/// A small shield-remaining indicator shown while a shield is active; it
/// flashes during the warning window so imminent expiry is clear from the
/// HUD too.
class _ShieldBadge extends StatelessWidget {
  const _ShieldBadge({required this.normalized, required this.expiring});

  final double normalized;
  final bool expiring;

  @override
  Widget build(BuildContext context) {
    final color = expiring ? const Color(0xFFFFB36A) : const Color(0xFF6FD3FF);
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.black45,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color, width: expiring ? 2 : 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.shield_rounded, color: color, size: 18),
            const SizedBox(width: 8),
            SizedBox(
              width: 96,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: normalized.clamp(0.0, 1.0),
                  minHeight: 7,
                  backgroundColor: Colors.white24,
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GameOverPanel extends StatelessWidget {
  const _GameOverPanel({required this.onRestart});

  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 22),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white24),
        ),
        child: WorldBuilder<(int, String?)>(
          select: (world) {
            final game = world.resource<GameState>();
            return (game.survivedTenths, game.lostReason);
          },
          builder: (context, run) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _shadowed('Game Over', fontSize: 32),
              const SizedBox(height: 8),
              _shadowed(run.$2 ?? '', fontSize: 18),
              const SizedBox(height: 4),
              _shadowed(
                'Survived ${(run.$1 / 10).toStringAsFixed(1)}s',
                fontSize: 16,
              ),
              const SizedBox(height: 18),
              IconButton.filled(
                tooltip: 'Restart',
                iconSize: 34,
                onPressed: onRestart,
                icon: const Icon(Icons.restart_alt_rounded),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
