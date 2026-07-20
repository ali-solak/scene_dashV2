/// The combat core, lifted from the framework's
/// `combat_machine_reference_test` (the suite came along:
/// `test/combat_reference_test.dart` runs against THIS code and must stay
/// green). Constants are the reference's, unchanged; the heavy attack
/// (task 8) is the one addition — hold-to-commit inside the same machine.
///
/// Everything here is pure gameplay (L1): no nodes, no materials, no clips.
/// Timing is `phase.elapsed`-driven throughout (L2).
library;

import 'package:scene_dash_v2/scene_dash_v2.dart';
import 'package:vector_math/vector_math.dart' show Vector3;

enum CombatPhase { idle, startup, active, recovery, rolling, staggered }

/// Buffered/held player intents. One button attacks — the hold decides
/// light vs heavy.
enum CombatAction { attack, roll }

/// The fighter's stance, derived from lock state by the lock-on system and
/// read by movement now and the animation mapper later.
enum Stance { free, locked }

// --- Reference constants (60 Hz; constants-only commits if tuning ever
// --- demands) ---

const double combatFixedDt = 1 / 60;

// Tuning pass (constants only — the lifted suite derives its expectations
// from these, so it stays exact): the light attack is markedly SNAPPIER so
// swings read as strikes rather than wind-ups.
// These windows are sized so a swing CLIP FITS INSIDE THEM.
//
// The clips are ~1.1 s (light) and ~1.63 s (heavy). With a 0.48 s window
// the mapper had two bad options and took turns at both: play the clip at
// 2.3x (fast-forwarded), or play it at 1x and cut it off mid
// follow-through (stops before it is done). Neither is fixable in the
// animator — the window was simply shorter than the motion.
//
// So the window grew instead. An attack is now a real commitment of
// ~0.7 s (light) and ~1.05 s (heavy), which is also the souls-like read
// we were after: you choose to swing and you live with it.
const double startupSeconds = 0.18;
const double activeSeconds = 0.12;
const double recoverySeconds = 0.41;

/// The heavy's tail is its own: the chop clip is half again as long as
/// the slice, and it needs the room to land.
const double heavyRecoverySeconds = 0.59;
const double rollSeconds = 0.45;
const double iFrameStart = 0.05;
const double iFrameEnd = 0.32;
const double staggerSeconds = 0.35;
/// Must comfortably outlast the LONGEST recovery ([heavyRecoverySeconds]).
///
/// At 0.40 it did not: once recovery grew to fit the swing clips, an
/// input buffered at the start of a recovery expired before the fighter
/// returned to idle, so the queued roll or follow-up was silently eaten.
/// A buffer shorter than the action it is meant to queue through is not a
/// buffer.
const double bufferWindow = 0.75;

// --- The heavy attack (task 8): one button, the charge idiom ---

/// Still holding attack this far into startup commits the heavy variant.
const double heavyThresholdSeconds = 0.22;

/// The heavy's longer windup, measured from the same startup entry.
const double heavyStartupSeconds = 0.34;

const double lightDamage = 25;
const double heavyDamage = 40;
const double lightHitstopSeconds = 0.035;

/// The heavy's freeze is the weight: longer, and paired with a hard
/// pushback (see `rules`).
///
/// Kept UNDER ~80ms deliberately. Hitstop only reads as impact while the
/// brain files it as part of the swing; past that it crosses over and
/// reads as the game hitching, which is exactly the complaint the
/// previous 0.12 drew.
const double heavyHitstopSeconds = 0.075;

/// Metres per second the victim is shoved on a connect; the heavy really
/// throws them.
const double lightKnockback = 3.5;
const double heavyKnockback = 9.0;

/// The souls fighter: one [Machine] owns the mode; systems act on its
/// edges. `heavy` is per-swing state, reset when a new startup begins.
final class Fighter {
  final phase = Machine<CombatPhase>(CombatPhase.idle);

  /// Promoted mid-startup by holding attack past [heavyThresholdSeconds];
  /// committed once promoted (releasing no longer downgrades).
  bool heavy = false;

  Stance stance = Stance.free;

  bool get iFramed =>
      phase.state == CombatPhase.rolling &&
      phase.elapsed >= iFrameStart &&
      phase.elapsed < iFrameEnd;
}

/// A connected hit against [target] (the reference suite's `IncomingHit`,
/// grown by Phase 3's resolution). Emitted by `rules`' overlap checks in
/// both directions; consumed by `applyDamage`, which owns the
/// i-frame/stagger/hitstop consequences the lifted suite pins.
final class HitLanded {
  final Entity target;
  final double damage;
  final bool heavy;

  /// World-space shove this connect puts on the victim (null = none):
  /// `applyDamage` hands it to their [Knockback].
  final Vector3? knockback;

  /// Whether this connect interrupts the victim's action. Poise: a light
  /// blow costs health and ground but does NOT cancel what you were
  /// doing — only heavy hits break a fighter's rhythm.
  final bool stagger;

  /// Whether this connect is a BLOW — something the clock should freeze
  /// for and throw sparks off. False for damage-over-time ticks: a burn
  /// that stuttered the game twice a second would make the whole fight
  /// feel broken, and it carries its own fire to look at.
  final bool impact;

  const HitLanded(
    this.target,
    this.damage, {
    this.heavy = false,
    this.knockback,
    this.stagger = true,
    this.impact = true,
  });
}

/// Ticks each fighter's machine, then transitions on time and buffered
/// intent. Compute stays on the component; effects live in systems acting
/// on the edges this leaves raised.
///
/// The startup case is the heavy attack: a quick press goes active at
/// [startupSeconds] on release; a press still held at
/// [heavyThresholdSeconds] commits the heavy, which goes active at
/// [heavyStartupSeconds] whether or not the button is released after.
void fighterDriver(World world) {
  final buffer = world.buffer<CombatAction>();
  final held = world.buttons<CombatAction>().pressed(CombatAction.attack);
  world.query<Fighter>().each((entity, fighter) {
    final phase = fighter.phase..tick(world.dt);
    switch (phase.state) {
      case CombatPhase.idle:
        if (buffer.consume(CombatAction.attack)) {
          fighter.heavy = false;
          phase.go(CombatPhase.startup);
        } else if (buffer.consume(CombatAction.roll)) {
          phase.go(CombatPhase.rolling);
        }
      case CombatPhase.startup:
        if (!fighter.heavy && held && phase.elapsed >= heavyThresholdSeconds) {
          fighter.heavy = true;
        }
        final windup = fighter.heavy ? heavyStartupSeconds : startupSeconds;
        if (phase.elapsed >= windup && (fighter.heavy || !held)) {
          phase.go(CombatPhase.active);
        }
      case CombatPhase.active:
        if (phase.elapsed >= activeSeconds) phase.go(CombatPhase.recovery);
      case CombatPhase.recovery:
        final tail =
            fighter.heavy ? heavyRecoverySeconds : recoverySeconds;
        if (phase.elapsed >= tail) phase.go(CombatPhase.idle);
      case CombatPhase.rolling:
        if (phase.elapsed >= rollSeconds) phase.go(CombatPhase.idle);
      case CombatPhase.staggered:
        if (phase.elapsed >= staggerSeconds) phase.go(CombatPhase.idle);
    }
  });
}

/// Getting staggered wipes buffered intent — a stale press must never fire
/// out of a hit. Reads the entry edge the same frame it was raised.
void clearBufferOnStagger(World world) {
  final buffer = world.buffer<CombatAction>();
  world.query<Fighter>().each((entity, fighter) {
    if (fighter.phase.justEntered(CombatPhase.staggered)) buffer.clear();
  });
}

/// The buffer ages on wall time, so hitstop cannot extend the press window.
void ageCombatBuffer(World world) {
  world
      .resource<InputBuffer<CombatAction>>()
      .advance(world.resource<FrameTime>().unscaledDelta);
}
