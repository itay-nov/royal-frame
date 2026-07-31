import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:royal_frame/main.dart';
import 'package:royal_frame/screens/update_required_screen.dart';
import 'package:royal_frame/screens/welcome_screen.dart';
import 'package:royal_frame/screens/main_menu_screen.dart';
import 'package:royal_frame/services/app_initializer.dart';
import 'package:royal_frame/utils/localization.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    resetAndroidMobileAdsInitializationForTesting();
  });

  const ready = StartupResult(
    initialName: null,
    updateRequired: false,
    initialLang: AppLang.en,
  );

  testWidgets('shows loading UI while initialization is pending', (
    tester,
  ) async {
    final completer = Completer<StartupResult>();

    await tester.pumpWidget(
      RoyalFrameBootstrap(initialize: () => completer.future),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(WelcomeScreen), findsNothing);

    completer.complete(ready);
    await tester.pumpAndSettle();
  });

  testWidgets('startup failure is recoverable and retry can succeed', (
    tester,
  ) async {
    var attempts = 0;

    await tester.pumpWidget(
      RoyalFrameBootstrap(
        initialize: () async {
          attempts++;
          if (attempts == 1) throw StateError('offline');
          return ready;
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Royal Frame could not start'), findsOneWidget);
    expect(find.text('Try Again'), findsOneWidget);

    await tester.tap(find.text('Try Again'));
    await tester.pumpAndSettle();

    expect(attempts, 2);
    expect(find.byType(WelcomeScreen), findsOneWidget);
  });

  testWidgets('retry after a later startup failure reuses App Check success', (
    tester,
  ) async {
    var attempts = 0;
    var activations = 0;
    AppInitializer.resetAppCheckActivationForTesting();

    await tester.pumpWidget(
      RoyalFrameBootstrap(
        initialize: () async {
          await AppInitializer.activateAppCheckOnceForTesting(() async {
            activations++;
          });
          attempts++;
          if (attempts == 1) throw StateError('later startup leg failed');
          return ready;
        },
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Try Again'));
    await tester.pumpAndSettle();

    expect(attempts, 2);
    expect(activations, 1);
    expect(find.byType(WelcomeScreen), findsOneWidget);
  });

  test(
    'Firebase Core initialization is skipped after the first success',
    () async {
      var initialized = false;
      var initializationCount = 0;

      Future<void> initialize() async {
        initializationCount++;
        initialized = true;
      }

      await initializeFirebaseOnce(
        isInitialized: () => initialized,
        initialize: initialize,
      );
      await initializeFirebaseOnce(
        isInitialized: () => initialized,
        initialize: initialize,
      );

      expect(initializationCount, 1);
    },
  );

  testWidgets('an Android update-policy result is preserved by startup', (
    tester,
  ) async {
    await tester.pumpWidget(
      RoyalFrameBootstrap(
        initialize: () async => const StartupResult(
          initialName: 'Arthur',
          updateRequired: true,
          initialLang: AppLang.en,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(UpdateRequiredScreen), findsOneWidget);
    expect(find.byType(WelcomeScreen), findsNothing);
  });

  test('a recovered name reaches MainMenu with empty preferences', () {
    const result = StartupResult(
      initialName: 'Recovered Arthur',
      updateRequired: false,
      initialLang: AppLang.en,
    );
    final home = buildRoyalFrameHome(
      updateRequired: result.updateRequired,
      initialName: result.initialName,
      initialLang: result.initialLang,
      onUpdateSatisfied: () {},
    );

    expect(home, isA<MainMenuScreen>());
    final menu = home as MainMenuScreen;
    expect(menu.initialPlayerName, 'Recovered Arthur');
    expect(
      resolveMainMenuPlayerName(
        savedName: null,
        initialPlayerName: menu.initialPlayerName,
      ),
      'Recovered Arthur',
    );
    expect(
      resolveMainMenuPlayerName(
        savedName: 'Saved Guinevere',
        initialPlayerName: menu.initialPlayerName,
      ),
      'Saved Guinevere',
    );
  });

  test('Android Mobile Ads are skipped outside Android', () async {
    var calls = 0;

    await initializeAndroidMobileAdsOnceForTesting(
      isAndroid: false,
      initialize: () async {
        calls++;
      },
    );

    expect(calls, 0);
  });

  test('Android Mobile Ads initialization is cached after success', () async {
    var calls = 0;

    Future<void> initialize() async {
      calls++;
    }

    await initializeAndroidMobileAdsOnceForTesting(
      isAndroid: true,
      initialize: initialize,
    );
    await initializeAndroidMobileAdsOnceForTesting(
      isAndroid: true,
      initialize: initialize,
    );

    expect(calls, 1);
  });
}
