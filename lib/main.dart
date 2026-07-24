import 'package:flutter/material.dart';

import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  await windowManager.ensureInitialized();

  const windowOptions = WindowOptions(
    size: Size(1280, 800),
    minimumSize: Size(800, 600),
    center: true,
    // backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden,
    title: 'Camellia Player',
  );

  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    // await windowManager.setAsFrameless();
    await windowManager.setHasShadow(false);
    // await windowManager.setBackgroundColor(Colors.transparent);
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(const CamelliaPlayerApp());
}

class CamelliaPlayerApp extends StatelessWidget {
  const CamelliaPlayerApp({super.key});

  @override
  Widget build(BuildContext context) {
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
