import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

import 'theme_constants.dart';
import 'services/app_initializer.dart';
import 'screens/welcome_screen.dart';
import 'screens/main_menu_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // אתחול פיירבייס עם האופציות שנוצרו ב-configure
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  if (!kIsWeb && Platform.isAndroid) {
    await MobileAds.instance.initialize();
    MobileAds.instance.updateRequestConfiguration(
      RequestConfiguration(testDeviceIds: ['9158A269B1F012D5358CF30498DBF532']),
    );
  }

  // App Check activation + stale guest-session validation.
  final String? initialName = await AppInitializer.initialize();

  runApp(RoyalFrameApp(initialName: initialName));
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
        colorSchemeSeed: kGold,
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
            textStyle: kTsButton,
            shape: const RoundedRectangleBorder(borderRadius: kBrSm),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: kGold,
            side: const BorderSide(color: kGold),
            textStyle: kTsButton,
            shape: const RoundedRectangleBorder(borderRadius: kBrSm),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(foregroundColor: kGoldLight),
        ),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: kBurgundyLight,
          behavior: SnackBarBehavior.floating,
          contentTextStyle: const TextStyle(
            color: kGoldLight,
            fontWeight: FontWeight.w600,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: kBrMd,
            side: const BorderSide(color: kGold, width: 1),
          ),
        ),
        dialogTheme: const DialogThemeData(
          backgroundColor: kBurgundyLight,
          shape: RoundedRectangleBorder(
            borderRadius: kBrLg,
            side: BorderSide(color: kGold, width: 1.5),
          ),
        ),
      ),
      home: initialName == null
          ? const WelcomeScreen()
          : const MainMenuScreen(),
    );
  }
}
