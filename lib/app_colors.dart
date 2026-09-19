import 'package:flutter/material.dart';

/// Centralized palette derived from the Camellia Player app icon
/// (the pink camellia). Everything that touches a color references
/// these tokens so the whole app can be re-themed by editing one place.
class AppColors {
  const AppColors._();

  /// Core pink from the app icon's petals and "C" mark.
  static const Color camellia = Color(0xFFE91E63);

  /// Slightly deeper magenta for hover / pressed accents.
  static const Color camelliaDeep = Color(0xFFAD1457);

  /// Warm, light surface tone tinted with the camellia hue. Used as the
  /// desktop panel background beneath dark video / audio artwork.
  static const Color panelDark = Color(0xFF1A1118);

  /// Even darker tone — for the player scaffold behind video so the
  /// camellia accent stays the only saturated color on screen.
  static const Color videoBackdrop = Color(0xFF120A10);
}
