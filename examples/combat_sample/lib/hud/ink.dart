/// One palette, so every screen reads as a set rather than as whatever
/// colour each widget reached for. Cold steel against the world's greens
/// and the fight's reds: the UI stays legible over grass, fire and blood
/// without competing with any of them.
///
/// Shared by the fight HUD, the skill menu, the title screen and the
/// loading screen — they are one interface, so they use one set of inks.
library;

import 'package:flutter/material.dart' show Color;

abstract final class HudInk {
  static const scrim = Color(0xE60B0C0D);
  static const panel = Color(0xFF141618);

  /// Text: bone for what matters, ash for what supports it.
  static const bone = Color(0xFFE8E3D9);
  static const ash = Color(0xFF8F8A80);

  /// Live/affordable/ready. The one accent.
  static const steel = Color(0xFF8FB6C6);

  /// Already yours.
  static const jade = Color(0xFF7E9E7A);

  /// Hairlines and frames.
  static const rule = Color(0x33E8E3D9);
  static const ruleFaint = Color(0x18E8E3D9);
}
