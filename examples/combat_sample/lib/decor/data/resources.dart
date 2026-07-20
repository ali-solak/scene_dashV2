part of '../decor.dart';

/// Enough to read as weather without becoming confetti. Each is a draw,
/// so this is also the budget — and now that the column is short and
/// close to the camera, the same count read as far busier than it did
/// spread over the old one.
const int _leafCount = 38;

/// The column the leaves fall through: a cylinder centred on the arena,
/// wide enough that they are never obviously spawning in a ring.
///
/// The ceiling is deliberately LOW. The camera sits behind the fighter
/// looking slightly down, so anything much above head height is out of
/// frame for the whole fight — leaves drifting at 14 units were falling
/// entirely above the screen. This keeps them in the band you actually
/// look at, and the tighter radius keeps them near the fight rather than
/// out over the treeline.
const double _leafFieldRadius = 15;
const double _leafCeiling = 5.5;

/// Fall speed range. A leaf is mostly air resistance, so this stays well
/// under gravity — but drifting too slowly reads as floating debris
/// rather than something falling.
const double _fallSlowest = 0.55;
const double _fallFastest = 1.25;

/// How hard the wind pushes a leaf sideways, per unit of
/// `WindState.strength`. The gust the grass leans in is the same gust
/// that carries these.
const double _windPush = 1.7;

/// Radians per second of tumble, and how far a leaf swings side to side
/// as it falls (leaves fall in a spiral, not a line).
const double _tumbleSlowest = 0.5;
const double _tumbleFastest = 2.2;
const double _swayAmplitude = 0.9;
const double _swaySlowest = 0.8;
const double _swayFastest = 2.0;

/// Big enough to read at combat distance. These are dressing seen from
/// nine metres away, not held up to the camera.
const double _leafSize = 0.22;

/// Feature-owned state: the per-leaf nodes plus packed animation data.
///
/// Packed parallel arrays rather than a list of objects, for the same
/// reason `scene_game`'s motes do it: this is touched every frame for
/// every leaf, and it is the one place in the sample where that pattern
/// actually earns its awkwardness.
final class LeafField {
  /// Built by `spawnLeaves`; empty until then (and forever headless).
  final List<Node> leaves = [];

  /// Drift position per leaf (x, y, z), packed.
  final Float32List position = Float32List(_leafCount * 3);

  /// Per-leaf fall speed, tumble rate, sway rate and sway phase.
  final Float32List fall = Float32List(_leafCount);
  final Float32List tumble = Float32List(_leafCount);
  final Float32List sway = Float32List(_leafCount);
  final Float32List phase = Float32List(_leafCount);

  /// Accumulated tumble angle, so rotation is continuous across frames.
  final Float32List spin = Float32List(_leafCount);

  /// The axis each leaf tumbles about (x, y, z), packed and normalised.
  final Float32List axis = Float32List(_leafCount * 3);
}
