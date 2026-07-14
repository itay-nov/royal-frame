import 'dart:async';
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
import 'utils/app_feedback.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const RoyalFrameBootstrap());
}

typedef AppInitialization = Future<String?> Function();

/// Keeps a Flutter-rendered recovery screen visible while native services
/// initialize. Previously, a Firebase/App Check exception happened before
/// [runApp], leaving users stuck on the launch screen with no way to retry.
class RoyalFrameBootstrap extends StatefulWidget {
  const RoyalFrameBootstrap({super.key, this.initialize});

  /// Injectable so startup success, failure, and retry behavior can be tested
  /// without contacting native services.
  final AppInitialization? initialize;

  @override
  State<RoyalFrameBootstrap> createState() => _RoyalFrameBootstrapState();
}

class _RoyalFrameBootstrapState extends State<RoyalFrameBootstrap> {
  late Future<String?> _initialization;

  @override
  void initState() {
    super.initState();
    _startInitialization();
  }

  void _startInitialization() {
    _initialization = _runInitialization();
  }

  Future<String?> _runInitialization() async {
    try {
      return await Future<String?>.sync(widget.initialize ?? _initializeApp);
    } catch (error, stack) {
      logError('startup.initialize', error, stack);
      Error.throwWithStackTrace(error, stack);
    }
  }

  Future<String?> _initializeApp() async {
    // A retry can occur after Firebase Core succeeded but a later startup step
    // failed. Do not attempt to create the default app twice.
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }

    // Ads are Android-only in this app and are not required to play. Keep an
    // SDK/network failure from blocking the entire application startup.
    if (!kIsWeb && Platform.isAndroid) {
      unawaited(_initializeMobileAds());
    }

    // App Check activation + stale guest-session validation.
    return AppInitializer.initialize();
  }

  Future<void> _initializeMobileAds() async {
    try {
      await MobileAds.instance.initialize();
      await MobileAds.instance.updateRequestConfiguration(
        RequestConfiguration(
          testDeviceIds: ['9158A269B1F012D5358CF30498DBF532'],
        ),
      );
    } catch (error, stack) {
      logError('startup.mobileAds', error, stack);
    }
  }

  void _retry() {
    setState(_startInitialization);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _initialization,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _StartupApp();
        }
        if (snapshot.hasError) {
          return _StartupApp(onRetry: _retry);
        }
        return RoyalFrameApp(initialName: snapshot.data);
      },
    );
  }
}

class _StartupApp extends StatelessWidget {
  const _StartupApp({this.onRetry});

  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Royal Frame',
      debugShowCheckedModeBanner: false,
      theme: _buildRoyalFrameTheme(),
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: onRetry == null
                  ? Semantics(
                      label: 'Starting Royal Frame',
                      child: const CircularProgressIndicator(color: kGold),
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.cloud_off_rounded,
                          size: 52,
                          color: kGold,
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          'Royal Frame couldn\'t start',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: kGoldLight,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Check your connection and try again.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white70),
                        ),
                        const SizedBox(height: 24),
                        FilledButton.icon(
                          onPressed: onRetry,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Try Again'),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class RoyalFrameApp extends StatelessWidget {
  final String? initialName;
  const RoyalFrameApp({super.key, this.initialName});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Royal Frame',
      debugShowCheckedModeBanner: false,
      theme: _buildRoyalFrameTheme(),
      home: initialName == null
          ? const WelcomeScreen()
          : const MainMenuScreen(),
    );
  }
}

ThemeData _buildRoyalFrameTheme() => ThemeData(
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
);
