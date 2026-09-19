import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'app_colors.dart';
import 'home_screen.dart';
import 'ios_home_screen.dart';

/// Main entry point for Camellia Player
/// Handles the supported Windows, macOS, and iOS platforms.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // The desktop player and window chrome are Windows- and macOS-only.
  if (isWindowsPlatform || isMacOSPlatform) {
    MediaKit.ensureInitialized();
    try {
      await _initDesktopWindow();
    } catch (e) {
      debugPrint('Desktop window initialization failed: $e');
    }
  }

  runApp(const CamelliaPlayerApp());
}

/// Initializes the Windows desktop window.
Future<void> _initDesktopWindow() async {
  await windowManager.ensureInitialized();

  const windowOptions = WindowOptions(
    size: Size(1280, 800),
    minimumSize: Size(800, 600),
    center: true,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden,
    title: 'Camellia Player',
  );

  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.setHasShadow(false);
    await windowManager.show();
    await windowManager.focus();
  });
}

/// Determines if the current platform is iOS
bool get isIOSPlatform {
  if (kIsWeb) return false;
  return defaultTargetPlatform == TargetPlatform.iOS;
}

/// Determines if the current platform is Windows.
bool get isWindowsPlatform {
  if (kIsWeb) return false;
  return defaultTargetPlatform == TargetPlatform.windows;
}

/// Determines if the current platform is macOS.
bool get isMacOSPlatform {
  if (kIsWeb) return false;
  return defaultTargetPlatform == TargetPlatform.macOS;
}

class CamelliaPlayerApp extends StatelessWidget {
  const CamelliaPlayerApp({super.key});

  @override
  Widget build(BuildContext context) {
    // iOS gets its native-style UI. The Material branch is the desktop UI
    // (Windows and macOS); keeping it as the fallback also lets widget tests
    // run on a macOS host.
    if (isIOSPlatform) {
      // iOS uses Cupertino design
      return const CupertinoApp(
        title: 'Camellia Player',
        debugShowCheckedModeBanner: false,
        theme: CupertinoThemeData(
          primaryColor: CupertinoColors.systemPink,
          brightness: Brightness.dark,
        ),
        home: IOSHomeScreen(),
      );
    }

    // Windows and macOS use Material design. Seeded from the camellia
    // pink so every accent (buttons, sliders, progress) automatically
    // tracks the app icon's hue.
    final darkScheme = ColorScheme.fromSeed(
      seedColor: AppColors.camellia,
      brightness: Brightness.dark,
    ).copyWith(
      // Re-tint the few surface roles to match the deep, slightly purple
      // panel tone behind the app icon, so the app does not look generic
      // M3-dark. These also flow into CustomTitleBar and the player.
      surface: AppColors.videoBackdrop,
      surfaceContainerLowest: AppColors.videoBackdrop,
      surfaceContainerLow: AppColors.panelDark,
      surfaceContainer: AppColors.panelDark,
      surfaceContainerHigh: const Color(0xFF22161D),
      surfaceContainerHighest: const Color(0xFF2A1B23),
      outlineVariant: const Color(0xFF3A2A33),
      primary: AppColors.camellia,
      secondary: const Color(0xFFF48FB1), // lighter camellia for the secondary slot
      tertiary: const Color(0xFFFFB3C7),
    );

    final lightScheme = ColorScheme.fromSeed(
      seedColor: AppColors.camellia,
      brightness: Brightness.light,
    );

    return MaterialApp(
      title: 'Camellia Player',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: lightScheme,
        scaffoldBackgroundColor: lightScheme.surface,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: darkScheme,
        scaffoldBackgroundColor: darkScheme.surface,
        sliderTheme: const SliderThemeData(
          activeTrackColor: AppColors.camellia,
          thumbColor: AppColors.camellia,
        ),
        progressIndicatorTheme: const ProgressIndicatorThemeData(
          color: AppColors.camellia,
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      home: const HomeScreen(),
    );
  }
}
