import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:royal_frame/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('player name input is capped at the backend limit', (
    tester,
  ) async {
    await tester.pumpWidget(const RoyalFrameApp());
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();

    final nameField = find.byType(TextField).first;
    await tester.enterText(nameField, List.filled(40, 'a').join());

    final field = tester.widget<TextField>(nameField);
    expect(field.controller!.text, hasLength(30));
  });

  testWidgets('empty guest name is rejected before authentication', (
    tester,
  ) async {
    await tester.pumpWidget(const RoyalFrameApp());
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Play as Guest'));
    await tester.pump();

    expect(find.text('Please enter a name'), findsOneWidget);
  });
}
