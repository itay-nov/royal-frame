import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:royal_frame/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('shows Flutter loading UI while services initialize', (
    tester,
  ) async {
    final initialization = Completer<String?>();

    await tester.pumpWidget(
      RoyalFrameBootstrap(initialize: () => initialization.future),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.bySemanticsLabel('Starting Royal Frame'), findsOneWidget);

    initialization.complete(null);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();

    expect(find.text('ROYAL FRAME'), findsOneWidget);
  });

  testWidgets('shows a recoverable error and retries initialization', (
    tester,
  ) async {
    var attempts = 0;

    Future<String?> initialize() {
      attempts++;
      if (attempts == 1) {
        return Future<String?>.error(StateError('startup failed'));
      }
      return Future<String?>.value(null);
    }

    await tester.pumpWidget(RoyalFrameBootstrap(initialize: initialize));
    await tester.pump();

    expect(find.text("Royal Frame couldn't start"), findsOneWidget);
    expect(find.text('Try Again'), findsOneWidget);

    await tester.tap(find.text('Try Again'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();

    expect(attempts, 2);
    expect(find.text('ROYAL FRAME'), findsOneWidget);
  });
}
