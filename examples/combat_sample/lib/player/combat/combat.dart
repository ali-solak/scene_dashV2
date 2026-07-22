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
// Light is the quick horizontal Slice (1.10 s) — fast and wide. Snappy
// window: it fits the clip at the playback cap (1.10 / 0.71 ≈ 1.55), so
// the whole swing plays and the contact lands in the active beat. The
// slice's connect is early and mid-body, so a short startup reads right —
// no long overhead windup to wait through. `startupSeconds` MUST stay
// under [heavyThresholdSeconds] (a release before the threshold fires a
// light, not the heavy — `heavy_promotion_test`).
const double startupSeconds = 0.18;
const double activeSeconds = 0.12;
const double recoverySeconds = 0.41;

// Heavy (the Spin, 2.40 s): a SWEEP, not a single blow. Its active window
// is long ([heavyActiveSeconds]) and it connects every [heavyHitInterval]
// while the axe comes round, so a body caught in it is struck — and
// reacts — several times. Windup + active + recovery ≈ 2.40 s, so the
// clip plays at its own speed instead of fast-forwarded.
const double heavyActiveSeconds = 1.20;
const double heavyRecoverySeconds = 0.60;

/// Seconds between the spin's connects — the axe comes around this often,
/// so this many taps of stagger land over [heavyActiveSeconds].
const double heavyHitInterval = 0.30;
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
/// Above [startupSeconds] so a quick tap resolves as a light before the
/// hold takes over.
const double heavyThresholdSeconds = 0.22;

/// The heavy's windup — the axe rears back before the spin. Above
/// [heavyThresholdSeconds] so the swing goes active AFTER the hold has
/// committed it; the spin's length lives in its long active sweep
/// ([heavyActiveSeconds]), not here.
const double heavyStartupSeconds = 0.62;

const double lightDamage = 25;

/// Per CONNECT, not per swing: the spin lands ~4 times over its sweep
/// ([heavyActiveSeconds] / [heavyHitInterval]), so the total is roughly
/// 4x this. Kept low so a full spin lands around 1.5x a chop rather than
/// obliterating the ring in one button.
const double heavyDamage = 14;

/// Metres per second the victim is shoved on a connect. The spin's is
/// small on purpose: it hits repeatedly, so a hard shove would fling the
/// victim clear of the sweep after the first tap. A light nudge keeps
/// them in range to be struck again.
const double lightKnockback = 3.5;
const double heavyKnockback = 2.5;

/// The souls fighter: one [Machine] owns the mode; systems act on its
/// edges. `heavy` is per-swing state, reset when a new startup begins.
final class Fighter {
  final phase = Machine<CombatPhase>(CombatPhase.idle);

  /// Promoted mid-startup by holding attack past [heavyThresholdSeconds];
  /// committed once promoted (releasing no longer downgrades).
  bool heavy = false;

  /// Connects emitted so far in the current active phase. The light lands
  /// one; the heavy spin lands one per [heavyHitInterval] as it sweeps, so
  /// `resolveStrikes` counts off this to fire each tap exactly once.
  int strikeHits = 0;

  Stance stance = Stance.free;

  /// Seconds since the last blow that cost this fighter health. Starts
  /// spent; ticked by [fighterDriver], zeroed by the damage path.
  ///
  /// Poise means an ordinary swing does NOT stagger you, and the animator
  /// only ever played its hit clip off the staggered phase — so a normal
  /// hit produced no reaction from the body at all. This is the flinch the
  /// mapper reads: a render input, never a gate on anything here.
  ///
  /// Lives on [Fighter] rather than on the motion component for a
  /// mechanical reason as much as a conceptual one: the damage path already
  /// writes `Fighter`, so this needs no new access declaration. On
  /// `PlayerMotion` it collided with the camera rig, which reads that
  /// component in the same system set.
  double sinceHurt = double.infinity;

  /// Seconds since the fighter last cast a leaping skill (the wind gust).
  /// Another render-only input: the mapper plays the jump off it (see the
  /// player animator's `update`), it gates nothing. Zeroed when
  /// [fighterDriver] sees a [CastLeap]. Starts spent.
  double sinceCast = double.infinity;

  bool get iFramed =>
      phase.state == CombatPhase.rolling &&
      phase.elapsed >= iFrameStart &&
      phase.elapsed < iFrameEnd;
}

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

  /// Whether this connect is a BLOW — something to throw sparks off. False
  /// for damage-over-time ticks: a burn carries its own fire to look at.
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

/// The player cast a skill it leaps for (the wind gust). Emitted by
/// `castSkills` (skills feature), read by [fighterDriver] to time the jump.
/// An event, not a direct write, so the skill never reaches into `Fighter`.
final class CastLeap {
  const CastLeap();
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
  // A wind gust cast this frame? The animator plays a leap off `sinceCast`.
  final leapt = world.events<CastLeap>().isNotEmpty;
  world.query<Fighter>().each((entity, fighter) {
    fighter.sinceHurt += world.dt;
    fighter.sinceCast += world.dt;
    if (leapt) fighter.sinceCast = 0;
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
        // The spin's contact sweep is long (it hits several times); the
        // chop's active is a single beat.
        final window = fighter.heavy ? heavyActiveSeconds : activeSeconds;
        if (phase.elapsed >= window) phase.go(CombatPhase.recovery);
      case CombatPhase.recovery:
        final tail = fighter.heavy ? heavyRecoverySeconds : recoverySeconds;
        // Recovery cancel: a roll buffered during the follow-through fires
        // at once, so committing to a swing is never a trap you cannot roll
        // out of. Only the ROLL cancels — a queued attack still waits for
        // idle, so mashing never chains swings for free.
        if (buffer.consume(CombatAction.roll)) {
          phase.go(CombatPhase.rolling);
        } else if (phase.elapsed >= tail) {
          phase.go(CombatPhase.idle);
        }
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
  world.resource<InputBuffer<CombatAction>>().advance(
    world.resource<FrameTime>().unscaledDelta,
  );
}
