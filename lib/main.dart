import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'home_screen.dart';
import 'ios_home_screen.dart';

/// Main entry point for Camellia Player
/// Handles the supported Windows and iOS platforms.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // The desktop player and window chrome are Windows-only.
  if (isWindowsPlatform) {
    MediaKit.ensureInitialized();
    try {
      await _initDesktopWindow();
    } catch (e) {
      debugPrint('Windows window initialization failed: $e');
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

class CamelliaPlayerApp extends StatelessWidget {
  const CamelliaPlayerApp({super.key});

  @override
  Widget build(BuildContext context) {
    // iOS gets its native-style UI. The Material branch is the Windows UI;
    // keeping it as the fallback also lets widget tests run on a macOS host.
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

    // Windows uses Material design.
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFFE91E63),
      brightness: Brightness.light,
    );
    final darkScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFFE91E63),
      brightness: Brightness.dark,
    );

    return MaterialApp(
      title: 'Camellia Player',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: scheme.surface,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: darkScheme,
        scaffoldBackgroundColor: darkScheme.surface,
      ),
      home: const HomeScreen(),
    );
  }
}
