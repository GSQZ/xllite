import 'package:flutter/material.dart';

/// A skin: the colour the app is built from, plus the tint of the wash
/// behind entry screens. Ten of them, so choosing feels like picking a
/// look rather than a hex value.
///
/// [color] seeds the Material scheme and is used verbatim as the light
/// primary, so every skin keeps white text on its buttons. [glow] is the
/// tint the decorative wash uses; a skin whose glow sits close to its seed
/// in saturation reads quiet (墨黑, 石墨, 素白), one that goes brighter
/// reads expressive (湖青, 胭脂).
enum ThemeSkin {
  campusBlue('校园蓝', Color(0xFF1D6FD8), Color(0xFF3C8BF0), Color(0xFF8AB4FF)),
  lakeTeal('湖青', Color(0xFF0B7A86), Color(0xFF13AEB4), Color(0xFF5AD3D6)),
  pineGreen('松绿', Color(0xFF2E7D4F), Color(0xFF46A472), Color(0xFF77C79C)),
  duskViolet('暮紫', Color(0xFF6A4FC8), Color(0xFF8B73E6), Color(0xFFB3A2F5)),
  rouge('胭脂', Color(0xFFC2416B), Color(0xFFDE6B90), Color(0xFFF09DB6)),
  ember('赭橙', Color(0xFFB5500F), Color(0xFFD97234), Color(0xFFF0A472)),
  coffee('咖啡', Color(0xFF7A5A3C), Color(0xFF9C7550), Color(0xFFC4A382)),
  graphite('石墨', Color(0xFF4A5568), Color(0xFF64748B), Color(0xFF93A3B8)),
  ink('墨黑', Color(0xFF232833), Color(0xFF3B4250), Color(0xFF6B7382)),
  paper('素白', Color(0xFF8A8378), Color(0xFFA79E90), Color(0xFFCFC7B8));

  const ThemeSkin(this.label, this.color, this._lightGlow, this._darkGlow);

  final String label;

  /// Seeds the scheme; also the light primary.
  final Color color;

  final Color _lightGlow;
  final Color _darkGlow;

  /// Tint of the decorative wash behind entry screens.
  Color glow(Brightness brightness) =>
      brightness == Brightness.dark ? _darkGlow : _lightGlow;
}

/// The skin a fresh install starts on.
const ThemeSkin defaultSkin = ThemeSkin.campusBlue;
