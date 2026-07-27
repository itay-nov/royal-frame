import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:royal_frame/screens/update_required_screen.dart';
import 'package:royal_frame/utils/localization.dart';

void main() {
  testWidgets('Android back navigation cannot dismiss the update screen', (
    tester,
  ) async {
    final navigatorKey = GlobalKey<NavigatorState>();

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: const Scaffold(body: Text('GAME')),
      ),
    );
    navigatorKey.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => UpdateRequiredScreen(
          lang: AppLang.en,
          onUpdateSatisfied: () {},
          checkUpdateRequired: () async => true,
          openPlayStore: () async => true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Update the game to continue.'), findsOneWidget);
    expect(find.text('GAME'), findsNothing);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('Update the game to continue.'), findsOneWidget);
    expect(find.text('GAME'), findsNothing);
  });

  testWidgets(
    'returning from the Play Store without updating remains blocked',
    (tester) async {
      var storeOpenCount = 0;
      var recheckCount = 0;
      var updateSatisfied = false;

      await tester.pumpWidget(
        MaterialApp(
          home: UpdateRequiredScreen(
            lang: AppLang.en,
            onUpdateSatisfied: () => updateSatisfied = true,
            checkUpdateRequired: () async {
              recheckCount++;
              return true;
            },
            openPlayStore: () async {
              storeOpenCount++;
              return true;
            },
          ),
        ),
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Update'));
      await tester.pump();
      expect(storeOpenCount, 1);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(recheckCount, 1);
      expect(updateSatisfied, isFalse);
      expect(find.text('Update the game to continue.'), findsOneWidget);
    },
  );
}
