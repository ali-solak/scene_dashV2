/// Where the app starts.
///
/// `main` calls [runCombatApp]: platform setup, then a black [MaterialApp]
/// whose only screen is [GameScreen] — which owns the game itself (boot,
/// the loading cover, and the scene view).
library;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/game_screen.dart';
import 'features/world/data/config.dart' as config;

Future<void> runCombatApp() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) {
    await BrowserContextMenu.disableContextMenu();
  } else if (config.isMobile) {
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }
  runApp(const CombatApp());
}

class CombatApp extends StatelessWidget {
  const CombatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(backgroundColor: Colors.black, body: GameScreen()),
    );
  }
}
