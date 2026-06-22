import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'firebase_options.dart';

import 'theme_constants.dart';
import 'screens/welcome_screen.dart';
import 'screens/main_menu_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // אתחול פיירבייס עם האופציות שנוצרו ב-configure
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  await FirebaseAppCheck.instance.activate(
    // Android/iOS: Play Integrity / App Attest in release; debug provider in debug.
    androidProvider: kReleaseMode ? AndroidProvider.playIntegrity : AndroidProvider.debug,
    appleProvider:   kReleaseMode ? AppleProvider.appAttest       : AppleProvider.debug,
    // Web: always pass the reCAPTCHA provider.
    // In debug/dev the JS global `self.FIREBASE_APPCHECK_DEBUG_TOKEN = true`
    // (set in web/index.html for localhost) intercepts the request before it
    // reaches reCAPTCHA, so no real token exchange happens and no 403 is thrown.
    // The SDK prints the debug UUID to the DevTools console automatically.
    // Register that UUID in: Firebase Console → App Check → Manage debug tokens.
    webProvider: ReCaptchaV3Provider('6LfKGSctAAAAAJ6Lk2FwIHMlemfc_BhiPAHjeXt9'),
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
            textStyle: const TextStyle(
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(foregroundColor: kGoldLight),
        ),
      ),
      home: initialName == null
          ? const WelcomeScreen()
          : const MainMenuScreen(),
    );
  }
}
