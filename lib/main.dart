import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

import 'theme_constants.dart';
import 'screens/welcome_screen.dart';
import 'screens/main_menu_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // אתחול פיירבייס עם האופציות שנוצרו ב-configure
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  final prefs = await SharedPreferences.getInstance();
  final String? savedName = prefs.getString('playerName');
  
  runApp(RoyalFrameApp(initialName: savedName));
}

class RoyalFrameApp extends StatelessWidget {
  final String? initialName;
  const RoyalFrameApp({super.key, this.initialName});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Royal Frame',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFFD4AF37),
        brightness: Brightness.dark,
        scaffoldBackgroundColor: kBurgundy,
        appBarTheme: const AppBarTheme(
          backgroundColor: kBurgundyLight,
          foregroundColor: kGold,
          elevation: 0,
          titleSpacing: 16,
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: kGold,
            foregroundColor: kBurgundy,
            textStyle: const TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(foregroundColor: kGoldLight),
        ),
      ),
      home: initialName == null ? const WelcomeScreen() : const MainMenuScreen(),
    );
  }
}