import 'package:flutter/material.dart';

/// Shared desktop theme selection. Dark is used until persisted settings load.
class AppThemeController {
  AppThemeController._();

  static final ValueNotifier<ThemeMode> mode = ValueNotifier(ThemeMode.dark);

  static void setMode(String value) {
    mode.value = value == 'light' ? ThemeMode.light : ThemeMode.dark;
  }
}
