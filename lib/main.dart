import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

import 'theme_constants.dart';
import 'services/app_initializer.dart';
import 'services/update_service.dart';
import 'screens/welcome_screen.dart';
import 'screens/main_menu_screen.dart';
import 'screens/update_required_screen.dart';
import 'utils/localization.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  if (!kIsWeb && Platform.isAndroid) {
    unawaited(() async {
      try {
        await initializeAndroidMobileAdsOnceForTesting(
          isAndroid: true,
          initialize: () async {
    await MobileAds.instance.initialize();
    MobileAds.instance.updateRequestConfiguration(
      RequestConfiguration(testDeviceIds: ['42AAA544A0427790DCDFA068D34E25CF']),
    );
          },
        );
      } catch (_) {
        debugPrint('[Startup] Android advertising initialization failed.');
      }
    }());
  }

  runApp(const RoyalFrameBootstrap());
}

typedef StartupInitialization = Future<StartupResult> Function();

Future<void>? _mobileAdsInitialization;

@visibleForTesting
Future<void> initializeAndroidMobileAdsOnceForTesting({
  required bool isAndroid,
  required Future<void> Function() initialize,
}) async {
  if (!isAndroid) return;
  final initialization = _mobileAdsInitialization ??= initialize();
  try {
    await initialization;
  } catch (_) {
    if (identical(_mobileAdsInitialization, initialization)) {
      _mobileAdsInitialization = null;
    }
    rethrow;
  }
}

@visibleForTesting
void resetAndroidMobileAdsInitializationForTesting() {
  _mobileAdsInitialization = null;
}

@immutable
class StartupResult {
  const StartupResult({
    required this.initialName,
    required this.updateRequired,
    required this.initialLang,
  });

  final String? initialName;
  final bool updateRequired;
  final AppLang initialLang;
}

@visibleForTesting
Future<void> initializeFirebaseOnce({
  required bool Function() isInitialized,
  required Future<void> Function() initialize,
}) async {
  if (!isInitialized()) {
    await initialize();
  }
}

class RoyalFrameBootstrap extends StatefulWidget {
  const RoyalFrameBootstrap({super.key, this.initialize});

  final StartupInitialization? initialize;

  @override
  State<RoyalFrameBootstrap> createState() => _RoyalFrameBootstrapState();
}

class _RoyalFrameBootstrapState extends State<RoyalFrameBootstrap> {
  late Future<StartupResult> _initialization;

  @override
  void initState() {
    super.initState();
    _startInitialization();
  }

  void _startInitialization() {
    _initialization = _runInitialization();
  }

  Future<StartupResult> _runInitialization() async {
    try {
      return await Future<StartupResult>.sync(
        widget.initialize ?? _initializeApp,
      );
    } catch (error, stack) {
      debugPrint('[Startup] Initialization failed.');
      Error.throwWithStackTrace(error, stack);
    }
  }

  void _retry() {
    setState(_startInitialization);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<StartupResult>(
      future: _initialization,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _StartupApp();
        }
        if (snapshot.hasError) {
          return _StartupApp(onRetry: _retry);
        }

        final result = snapshot.requireData;
        return RoyalFrameApp(
          initialName: result.initialName,
          updateRequired: result.updateRequired,
          initialLang: result.initialLang,
        );
      },
    );
  }
  }

Future<StartupResult> _initializeApp() async {
  await initializeFirebaseOnce(
    isInitialized: () => Firebase.apps.isNotEmpty,
    initialize: () =>
        Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform),
  );


  // App Check/session validation and the Android minimum-build check are
  // independent.
  final startupResults = await Future.wait<Object?>([
    AppInitializer.initialize(),
    UpdateService.isUpdateRequired(),
    L.loadLang(),
  ]);

  return StartupResult(
      initialName: startupResults[0] as String?,
      updateRequired: startupResults[1] as bool,
      initialLang: startupResults[2] as AppLang,
  );
}

class _StartupApp extends StatelessWidget {
  const _StartupApp({this.onRetry});

  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Royal Frame',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: kGold,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: kBurgundy,
      ),
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
                          'Royal Frame could not start',
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

@visibleForTesting
Widget buildRoyalFrameHome({
  required bool updateRequired,
  required String? initialName,
  required AppLang initialLang,
  required VoidCallback onUpdateSatisfied,
}) {
  if (updateRequired) {
    return UpdateRequiredScreen(
      lang: initialLang,
      onUpdateSatisfied: onUpdateSatisfied,
    );
  }
  if (initialName == null) return const WelcomeScreen();
  return MainMenuScreen(initialPlayerName: initialName);
}

class RoyalFrameApp extends StatefulWidget {
  final String? initialName;
  final bool updateRequired;
  final AppLang initialLang;

  const RoyalFrameApp({
    super.key,
    this.initialName,
    this.updateRequired = false,
    this.initialLang = AppLang.en,
  });

  @override
  State<RoyalFrameApp> createState() => _RoyalFrameAppState();
}

class _RoyalFrameAppState extends State<RoyalFrameApp> {
  late bool _updateRequired;

  @override
  void initState() {
    super.initState();
    _updateRequired = widget.updateRequired;
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.light,
        systemNavigationBarDividerColor: Colors.transparent,
        systemNavigationBarContrastEnforced: false,
        systemStatusBarContrastEnforced: false,
      ),
    );
  }

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
      home: buildRoyalFrameHome(
        updateRequired: _updateRequired,
        initialName: widget.initialName,
        initialLang: widget.initialLang,
        onUpdateSatisfied: () {
          if (mounted) setState(() => _updateRequired = false);
        },
      ),
    );
  }
}
