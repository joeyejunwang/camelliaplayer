import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'home_screen.dart';
import 'ios_home_screen.dart';

/// Main entry point for Camellia Player
/// Handles Windows desktop, iOS, and Web platforms
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Only initialize MediaKit and window_manager on platforms that support them
  if (isDesktopPlatform) {
    MediaKit.ensureInitialized();
    try {
      await _initDesktopWindow();
    } catch (e) {
      // window_manager not supported on this platform; continue silently
      debugPrint('Window manager init skipped: $e');
    }
  }

  runApp(const CamelliaPlayerApp());
}

/// Initialize window for desktop platforms
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

/// Determines if the current platform supports window_manager
bool get isDesktopPlatform {
  if (kIsWeb) return false;
  return !isIOSPlatform && defaultTargetPlatform != TargetPlatform.android;
}

class CamelliaPlayerApp extends StatelessWidget {
  const CamelliaPlayerApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Use iOS home screen for iOS devices, desktop home screen for others
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

    // Windows, Web, Android use Material design
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
